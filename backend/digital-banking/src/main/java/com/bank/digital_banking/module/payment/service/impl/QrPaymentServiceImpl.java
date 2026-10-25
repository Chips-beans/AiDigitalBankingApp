package com.bank.digital_banking.module.payment.service.impl;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.account.entity.AccountStatus;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.payment.dto.*;
import com.bank.digital_banking.module.payment.entity.Payment;
import com.bank.digital_banking.module.payment.entity.PaymentStatus;
import com.bank.digital_banking.module.payment.qr.EmvcoQrCode;
import com.bank.digital_banking.module.payment.qr.QrCodeEngine;
import com.bank.digital_banking.module.payment.repository.PaymentRepository;
import com.bank.digital_banking.module.payment.service.QrPaymentService;
import com.bank.digital_banking.module.transaction.dto.TransactionResponseDto;
import com.bank.digital_banking.module.transaction.entity.TransactionType;
import com.bank.digital_banking.module.transaction.service.FinancialCommandService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class QrPaymentServiceImpl implements QrPaymentService {

    private final QrCodeEngine qrCodeEngine;
    private final PaymentRepository paymentRepository;
    private final AccountRepository accountRepository;
    private final FinancialCommandService commandService;
    private final AuditTrail audit;

    @Override
    @Transactional
    public QrGenerateResponse generateQr(User user, QrGenerateRequest request) {
        Account account = requireOwner(user, request.accountNumber());

        String payeeName = resolveDisplayName(account.getUser());
        boolean dynamic = request.amount() != null && request.amount().compareTo(BigDecimal.ZERO) > 0;
        if ("STATIC".equalsIgnoreCase(request.qrType())) {
            dynamic = false;
        } else if ("DYNAMIC".equalsIgnoreCase(request.qrType())) {
            dynamic = true;
        }

        QrCodeEngine.GenerateOptions options = new QrCodeEngine.GenerateOptions(
                request.accountNumber(),
                payeeName,
                request.amount(),
                request.currency(),
                request.remark(),
                request.billNumber(),
                null,
                dynamic
        );

        EmvcoQrCode qrCode = qrCodeEngine.generate(options);

        Payment payment = Payment.builder()
                .md5Hash(qrCode.getQrHash())
                .accountNumber(request.accountNumber())
                .amount(qrCode.getAmount() != null ? qrCode.getAmount() : BigDecimal.ZERO)
                .currency(qrCode.getCurrency())
                .qrString(qrCode.getQrString())
                .status(PaymentStatus.PENDING)
                .build();

        paymentRepository.save(payment);
        audit.successAs(user, "PAYMENT", "QR_CREATED", payment.getId().toString());

        Map<String, String> payloadComponents = new LinkedHashMap<>();
        payloadComponents.put("accountNumber", qrCode.getAccountNumber());
        payloadComponents.put("accountIdentifier", qrCode.getAccountIdentifier());
        payloadComponents.put("payeeName", qrCode.getPayeeName());
        payloadComponents.put("currency", qrCode.getCurrency());
        payloadComponents.put("currencyCode", qrCode.getCurrencyNumericCode());
        if (qrCode.getAmount() != null) {
            payloadComponents.put("amount", qrCode.getAmount().toPlainString());
        }
        payloadComponents.put("qrType", qrCode.isDynamic() ? "DYNAMIC" : "STATIC");
        payloadComponents.put("countryCode", qrCode.getCountryCode());
        payloadComponents.put("merchantCity", qrCode.getMerchantCity());
        payloadComponents.put("acquiringBank", qrCode.getAcquiringBank());
        payloadComponents.put("crc", qrCode.getCrc());
        if (qrCode.getRemark() != null) {
            payloadComponents.put("remark", qrCode.getRemark());
        }
        if (qrCode.getBillNumber() != null) {
            payloadComponents.put("billNumber", qrCode.getBillNumber());
        }

        return new QrGenerateResponse(
                qrCode.getQrString(),
                qrCode.getQrHash(),
                qrCode.getQrHash(),
                qrCode.getAccountNumber(),
                payeeName,
                qrCode.getAmount(),
                qrCode.getCurrency(),
                qrCode.isDynamic() ? "DYNAMIC" : "STATIC",
                payment.getStatus(),
                request.remark(),
                request.billNumber(),
                qrCode.getAcquiringBank(),
                payloadComponents,
                payment.getCreatedAt()
        );
    }


    @Override
    @Transactional(readOnly = true)
    public QrScanResponse scanQr(User user, QrScanRequest request) {
        EmvcoQrCode qrCode = qrCodeEngine.parse(request.qrString());

        Account destinationAccount = accountRepository.findByAccountNumber(qrCode.getAccountNumber())
                .orElseThrow(() -> new ResourceNotFoundException("Destination account not found in system: " + qrCode.getAccountNumber()));

        if (destinationAccount.getStatus() != AccountStatus.ACTIVE) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "ACCOUNT_INACTIVE", "Destination account is inactive");
        }

        String destinationName = resolveDisplayName(destinationAccount.getUser());

        boolean isAlreadyPaid = false;
        var existingPayment = paymentRepository.findByQrHash(qrCode.getQrHash());
        if (existingPayment.isPresent() && existingPayment.get().getStatus() == PaymentStatus.SUCCESS) {
            isAlreadyPaid = true;
        }

        return new QrScanResponse(
                true,
                qrCode.getQrString(),
                qrCode.getQrHash(),
                destinationAccount.getAccountNumber(),
                destinationName,
                qrCode.getAmount(),
                qrCode.getCurrency(),
                qrCode.isDynamic(),
                qrCode.getAcquiringBank(),
                qrCode.getRemark(),
                qrCode.getBillNumber(),
                isAlreadyPaid
        );
    }

    @Override
    @Transactional
    public QrTransferResponse processQrTransfer(User user, String idempotencyKey, QrTransferRequest request) {
        EmvcoQrCode qrCode = qrCodeEngine.parse(request.qrString());

        String destinationAccountNumber = qrCode.getAccountNumber();
        if (request.sourceAccountNumber().equals(destinationAccountNumber)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Cannot transfer to the same account");
        }

        Account sourceAccount = requireOwner(user, request.sourceAccountNumber());
        if (sourceAccount.getStatus() != AccountStatus.ACTIVE) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "ACCOUNT_INACTIVE", "Source account is inactive");
        }

        Account destinationAccount = accountRepository.findByAccountNumber(destinationAccountNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Destination account not found in system: " + destinationAccountNumber));
        if (destinationAccount.getStatus() != AccountStatus.ACTIVE) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "ACCOUNT_INACTIVE", "Destination account is inactive");
        }

        // Determine transfer amount
        BigDecimal amountToTransfer;
        if (qrCode.isDynamic() && qrCode.getAmount() != null) {
            amountToTransfer = qrCode.getAmount();
            if (request.amount() != null && request.amount().compareTo(amountToTransfer) != 0) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "AMOUNT_MISMATCH",
                        "Specified amount does not match the QR code invoice amount (" + amountToTransfer + ")");
            }
        } else {
            if (request.amount() == null || request.amount().compareTo(BigDecimal.ZERO) <= 0) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "AMOUNT_REQUIRED", "Transfer amount must be greater than zero");
            }
            amountToTransfer = request.amount();
        }

        // Determine currency
        String transferCurrency = request.currency() != null && !request.currency().isBlank()
                ? request.currency().trim().toUpperCase()
                : qrCode.getCurrency();

        if (!sourceAccount.getCurrency().equalsIgnoreCase(transferCurrency)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CURRENCY_MISMATCH",
                    "Source account currency (" + sourceAccount.getCurrency() + ") does not match transfer currency (" + transferCurrency + ")");
        }

        // Verify if already paid (for dynamic QR)
        var existingPayment = paymentRepository.findByQrHash(qrCode.getQrHash());
        if (existingPayment.isPresent() && existingPayment.get().getStatus() == PaymentStatus.SUCCESS) {
            throw new ApiException(HttpStatus.CONFLICT, "PAYMENT_ALREADY_COMPLETED", "This QR code payment has already been completed");
        }

        String remark = request.remark() != null && !request.remark().trim().isEmpty()
                ? request.remark().trim()
                : (qrCode.getRemark() != null ? qrCode.getRemark() : "QR Code Transfer");

        String effectiveKey = idempotencyKey;
        if (effectiveKey == null || effectiveKey.isBlank()) {
            effectiveKey = "QR-" + qrCode.getQrHash().substring(0, 16) + "-" + System.currentTimeMillis();
        }

        // Execute atomic double-entry transfer via FinancialCommandService
        TransactionResponseDto txn = commandService.execute(
                user,
                TransactionType.TRANSFER,
                effectiveKey,
                sourceAccount.getAccountNumber(),
                destinationAccountNumber,
                amountToTransfer,
                transferCurrency,
                remark
        );

        // Update payment record status if present
        existingPayment.ifPresent(p -> {
            p.setStatus(PaymentStatus.SUCCESS);
            paymentRepository.save(p);
        });

        audit.successAs(user, "PAYMENT", "QR_TRANSFER_COMPLETED", txn.getReferenceNumber());

        return new QrTransferResponse(
                txn.getReferenceNumber(),
                "COMPLETED",
                sourceAccount.getAccountNumber(),
                destinationAccountNumber,
                resolveDisplayName(destinationAccount.getUser()),
                amountToTransfer,
                transferCurrency,
                remark,
                LocalDateTime.now()
        );
    }

    @Override
    @Transactional
    public PaymentCheckStatusResponse verifyPaymentStatus(User user, String qrHash) {
        Payment payment = paymentRepository.findByQrHash(qrHash)
                .orElseThrow(() -> new ResourceNotFoundException("Payment not available"));
        requireOwner(user, payment.getAccountNumber());

        boolean isPaid = payment.getStatus() == PaymentStatus.SUCCESS;
        return new PaymentCheckStatusResponse(qrHash, payment.getStatus(), isPaid);
    }

    @Override
    @Transactional
    public void processWebhookNotification(QrWebhookPayload payload) {
        paymentRepository.findByQrHash(payload.md5()).ifPresent(payment -> {
            if (payment.getStatus() != PaymentStatus.SUCCESS) {
                payment.setStatus(PaymentStatus.SUCCESS);
                paymentRepository.save(payment);
            }
        });
    }

    private Account requireOwner(User user, String accountNumber) {
        Account account = accountRepository.findByAccountNumber(accountNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Payment account not available"));
        if (!account.getUser().getId().equals(user.getId())) {
            throw new ResourceNotFoundException("Payment account not available");
        }
        return account;
    }

    private String resolveDisplayName(User user) {
        if (user == null) return "Digital Bank User";
        if (user.getFirstName() != null && user.getLastName() != null) {
            String full = (user.getFirstName() + " " + user.getLastName()).trim();
            if (!full.isEmpty()) return full;
        }
        return user.getUsername() != null ? user.getUsername() : "Digital Bank User";
    }
}
