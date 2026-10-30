package com.bank.digital_banking.module.payment.service.impl;

import com.bank.digital_banking.common.exception.*;
import com.bank.digital_banking.common.util.*;
import com.bank.digital_banking.module.account.entity.*;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.payment.dto.*;
import com.bank.digital_banking.module.payment.entity.*;
import com.bank.digital_banking.module.payment.qr.*;
import com.bank.digital_banking.module.payment.repository.PaymentRepository;
import com.bank.digital_banking.module.payment.service.QrPaymentService;
import com.bank.digital_banking.module.transaction.entity.TransactionType;
import com.bank.digital_banking.module.transaction.service.FinancialCommandService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.util.*;

@Service
@RequiredArgsConstructor
public class QrPaymentServiceImpl implements QrPaymentService {
    private final QrCodeEngine engine;
    private final QrProperties properties;
    private final PaymentRepository payments;
    private final AccountRepository accounts;
    private final FinancialCommandService commands;
    private final AuditTrail audit;
    private final JdbcTemplate jdbc;
    private final ObjectMapper json;
    private final TransactionLockPolicy locks;
    private final jakarta.persistence.EntityManager entities;

    @Override @Transactional
    public QrGenerateResponse generateQr(User user, QrGenerateRequest request) {
        locks.apply();
        Account account = owner(user, request.accountNumber());
        account = accounts.findLockedByNumber(account.getAccountNumber()).orElseThrow();
        entities.refresh(account, jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);
        active(account);
        String currency = CurrencyUtils.currency(request.currency());
        if (!account.getCurrency().equals(currency)) throw bad("CURRENCY_MISMATCH", "QR currency must match its account");
        boolean dynamic = request.amount() != null && request.amount().signum() > 0;
        if (request.qrType() != null) {
            if (!Set.of("STATIC", "DYNAMIC").contains(request.qrType().toUpperCase(Locale.ROOT)))
                throw bad("INVALID_REQUEST", "Choose STATIC or DYNAMIC");
            dynamic = "DYNAMIC".equalsIgnoreCase(request.qrType());
        }
        if (request.amount() != null) CurrencyUtils.amount(request.amount(), currency, true);
        if (dynamic && (request.amount() == null || request.amount().signum() <= 0))
            throw bad("INVALID_AMOUNT", "A fixed request requires a positive amount");
        if (!dynamic && request.amount() != null && request.amount().signum() != 0)
            throw bad("INVALID_AMOUNT", "A reusable QR cannot contain an amount");
        if (request.remark() != null && request.remark().length() > 50)
            throw bad("INVALID_REQUEST", "QR remark must be at most 50 characters");
        if (!dynamic) {
            var previous = payments.findFirstByAccountNumberAndQrTypeOrderByIdAsc(account.getAccountNumber(), "STATIC");
            if (previous.isPresent()) return response(previous.get(), account);
        }
        String bill = dynamic ? UUID.randomUUID().toString().replace("-", "") : null;
        var qr = engine.generate(new QrCodeEngine.GenerateOptions(account.getAccountNumber(), name(account.getUser()),
                dynamic ? request.amount() : null, currency, dynamic ? request.remark() : null, bill, null, dynamic));
        Payment payment = payments.saveAndFlush(Payment.builder().md5Hash(qr.getQrHash())
                .accountNumber(account.getAccountNumber()).amount(dynamic ? request.amount() : BigDecimal.ZERO)
                .currency(currency).qrString(qr.getQrString()).qrType(dynamic ? "DYNAMIC" : "STATIC")
                .status(PaymentStatus.PENDING).build());
        audit.successAs(user, "PAYMENT", "QR_CREATED", payment.getId().toString());
        return response(payment, account);
    }

    private QrGenerateResponse response(Payment payment, Account account) {
        var qr = engine.parse(payment.getQrString());
        Map<String, String> components = new LinkedHashMap<>();
        components.put("accountNumber", qr.getAccountNumber());
        components.put("accountIdentifier", qr.getAccountIdentifier());
        components.put("payeeName", name(account.getUser()));
        components.put("currency", qr.getCurrency());
        components.put("currencyCode", qr.getCurrencyNumericCode());
        components.put("qrType", payment.getQrType());
        components.put("countryCode", qr.getCountryCode());
        components.put("merchantCity", qr.getMerchantCity());
        components.put("acquiringBank", qr.getAcquiringBank());
        components.put("crc", qr.getCrc());
        if (qr.getAmount() != null) components.put("amount", qr.getAmount().toPlainString());
        return new QrGenerateResponse(qr.getQrString(), qr.getQrHash(), qr.getQrHash(), account.getAccountNumber(),
                name(account.getUser()), qr.getAmount(), qr.getCurrency(), payment.getQrType(), payment.getStatus(),
                qr.getRemark(), qr.getBillNumber(), qr.getAcquiringBank(), components, payment.getCreatedAt());
    }

    @Override @Transactional
    public KhqrGenerateResponse generateKhqr(User user, KhqrGenerateRequest request) {
        var qr = generateQr(user, new QrGenerateRequest(request.accountNumber(), request.amount(), request.currency(), null, null, null));
        return new KhqrGenerateResponse(qr.qrString(), qr.md5Hash(), qr.accountNumber(), request.amount(), qr.currency());
    }

    private Payment registered(EmvcoQrCode qr, boolean lock) {
        Payment payment = (lock ? payments.findLockedByHash(qr.getQrHash()) : payments.findByQrHash(qr.getQrHash()))
                .orElseThrow(() -> bad("UNSUPPORTED_QR", "Only registered Kesor account QR codes are supported"));
        if (lock) entities.refresh(payment, jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);
        if (!qr.getQrString().equals(payment.getQrString()) || !qr.getAccountNumber().equals(payment.getAccountNumber())
                || !qr.getCurrency().equals(payment.getCurrency())
                || !Objects.equals(qr.getAccountSubTags().get(EmvcoTag.SUBTAG_GUID), properties.getGuid())
                || qr.isDynamic() != "DYNAMIC".equals(payment.getQrType())
                || (qr.isDynamic() && (qr.getAmount() == null || qr.getAmount().compareTo(payment.getAmount()) != 0)))
            throw bad("UNSUPPORTED_QR", "QR does not match a registered Kesor request");
        if (qr.getAmount() != null) CurrencyUtils.amount(qr.getAmount(), qr.getCurrency(), false);
        return payment;
    }

    @Override @Transactional(readOnly = true)
    public QrScanResponse scanQr(User user, QrScanRequest request) {
        var qr = engine.parse(request.qrString());
        var payment = registered(qr, false);
        var destination = destination(qr.getAccountNumber(), qr.getCurrency());
        return new QrScanResponse(true, qr.getQrString(), qr.getQrHash(), destination.getAccountNumber(),
                name(destination.getUser()), qr.getAmount(), qr.getCurrency(), qr.isDynamic(), qr.getAcquiringBank(),
                qr.getRemark(), qr.getBillNumber(), qr.isDynamic() && payment.getStatus() == PaymentStatus.SUCCESS);
    }

    @Override @Transactional
    public QrTransferResponse processQrTransfer(User user, String key, QrTransferRequest request) {
        if (key == null || !key.matches("[A-Za-z0-9._:-]{1,128}"))
            throw bad("IDEMPOTENCY_KEY_REQUIRED", "Provide an Idempotency-Key");
        if (request.qrString() == null || request.qrString().length() > 4096)
            throw bad("INVALID_QR_CODE", "Invalid QR payload");
        locks.apply();
        String hash = HashUtils.sha256(json.writeValueAsString(Arrays.asList(request.sourceAccountNumber(),
                request.qrString(), request.amount() == null ? null : request.amount().stripTrailingZeros().toPlainString(),
                request.currency(), request.remark())));
        jdbc.update("INSERT INTO qr_transfer_requests(actor_user_id,request_key,request_hash) VALUES (?,?,?) ON CONFLICT DO NOTHING", user.getId(), key, hash);
        var claim = jdbc.queryForMap("SELECT request_hash,response_json FROM qr_transfer_requests WHERE actor_user_id=? AND request_key=? FOR UPDATE", user.getId(), key);
        if (!hash.equals(claim.get("request_hash")))
            throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_CONFLICT", "QR payment key belongs to a different request");
        if (claim.get("response_json") != null)
            return json.readValue((String) claim.get("response_json"), QrTransferResponse.class);
        var qr = engine.parse(request.qrString());
        var payment = registered(qr, true);
        var source = owner(user, request.sourceAccountNumber());
        var destination = destination(qr.getAccountNumber(), qr.getCurrency());
        active(source);
        String currency = request.currency() == null ? qr.getCurrency() : CurrencyUtils.currency(request.currency());
        if (!currency.equals(qr.getCurrency()) || !currency.equals(source.getCurrency()))
            throw bad("CURRENCY_MISMATCH", "Source, destination and QR currencies must match");
        if (source.getAccountNumber().equals(destination.getAccountNumber()))
            throw bad("INVALID_REQUEST", "Choose a different destination account");
        BigDecimal amount = CurrencyUtils.amount(qr.isDynamic() ? qr.getAmount() : request.amount(), currency, false);
        if (qr.isDynamic() && request.amount() != null && request.amount().compareTo(amount) != 0)
            throw bad("AMOUNT_MISMATCH", "Amount does not match the fixed request");
        if (qr.isDynamic() && payment.getStatus() == PaymentStatus.SUCCESS)
            throw new ApiException(HttpStatus.CONFLICT, "PAYMENT_ALREADY_COMPLETED", "This request has already been paid");
        String remark = request.remark() == null ? qr.getRemark() : request.remark();
        var transaction = commands.executeQr(user, key,
                source.getAccountNumber(), destination.getAccountNumber(), amount, currency, remark);
        if (qr.isDynamic()) {
            payment.setStatus(PaymentStatus.SUCCESS);
            payment.setTransactionId(transaction.getId());
            payments.save(payment);
        }
        var response = new QrTransferResponse(transaction.getReferenceNumber(), "COMPLETED", source.getAccountNumber(),
                destination.getAccountNumber(), name(destination.getUser()), amount, currency, remark,
                transaction.getCreatedAt().toLocalDateTime(), transaction);
        jdbc.update("UPDATE qr_transfer_requests SET response_json=? WHERE actor_user_id=? AND request_key=?",
                json.writeValueAsString(response), user.getId(), key);
        audit.successAs(user, "PAYMENT", "QR_TRANSFER_COMPLETED", transaction.getReferenceNumber());
        return response;
    }

    @Override @Transactional(readOnly = true)
    public PaymentCheckStatusResponse verifyPaymentStatus(User user, String hash) {
        var payment = payments.findByQrHash(hash).orElseThrow(() -> new ResourceNotFoundException("Payment not available"));
        owner(user, payment.getAccountNumber());
        boolean paid = "DYNAMIC".equals(payment.getQrType()) && payment.getStatus() == PaymentStatus.SUCCESS;
        return new PaymentCheckStatusResponse(hash, paid ? PaymentStatus.SUCCESS : PaymentStatus.PENDING, paid);
    }
    @Override public void processWebhookNotification(QrWebhookPayload payload) {
        throw new org.springframework.security.access.AccessDeniedException("External settlement is not enabled");
    }
    private Account owner(User user, String number) {
        var account = accounts.findByAccountNumber(number).orElseThrow(() -> new ResourceNotFoundException("Account not available"));
        if (!account.getUser().getId().equals(user.getId())) throw new ResourceNotFoundException("Account not available");
        return account;
    }
    private Account destination(String number, String currency) {
        var account = accounts.findByAccountNumber(number).orElseThrow(() -> new ResourceNotFoundException("Destination account not available"));
        active(account);
        if (!account.getCurrency().equals(currency)) throw bad("CURRENCY_MISMATCH", "QR currency must match destination account");
        return account;
    }
    private static void active(Account account) {
        if (account.getStatus() != AccountStatus.ACTIVE) throw bad("ACCOUNT_INACTIVE", "Account is not active");
    }
    private static ApiException bad(String code, String message) { return new ApiException(HttpStatus.BAD_REQUEST, code, message); }
    private static String name(User user) {
        String name = ((user.getFirstName() == null ? "" : user.getFirstName()) + " " + (user.getLastName() == null ? "" : user.getLastName())).trim();
        return name.isEmpty() ? user.getUsername() : name;
    }
}
