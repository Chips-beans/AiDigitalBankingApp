package com.bank.digital_banking.module.payment.service.impl;

import com.bank.digital_banking.module.payment.adapter.BakongAdapter;
import com.bank.digital_banking.module.payment.dto.*;
import com.bank.digital_banking.module.payment.entity.Payment;
import com.bank.digital_banking.module.payment.entity.PaymentStatus;
import com.bank.digital_banking.module.payment.repository.PaymentRepository;
import com.bank.digital_banking.module.payment.service.BakongService;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.auth.entity.User;
import kh.gov.nbc.bakong_khqr.model.KHQRData;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class BakongServiceImpl implements BakongService {

    private final BakongAdapter bakongAdapter;
    private final PaymentRepository paymentRepository;
    private final AccountRepository accountRepository;

    @Override
    @Transactional
    public KhqrGenerateResponse generateKhqr(User user, KhqrGenerateRequest request) {
        requireOwner(user, request.accountNumber());
        String bakongAccountId = request.accountNumber() + "@digitalbank";
        
        KHQRData khqrData = bakongAdapter.generateIndividualKhqr(
                bakongAccountId,
                "Digital Bank User",
                request.amount().doubleValue(),
                request.currency()
        );

        Payment payment = Payment.builder()
                .md5Hash(khqrData.getMd5())
                .accountNumber(request.accountNumber())
                .amount(request.amount())
                .currency(request.currency())
                .qrString(khqrData.getQr())
                .status(PaymentStatus.PENDING)
                .build();

        paymentRepository.save(payment);

        return new KhqrGenerateResponse(
                khqrData.getQr(),
                khqrData.getMd5(),
                request.accountNumber(),
                request.amount().doubleValue(),
                request.currency()
        );
    }

    @Override
    @Transactional
    public PaymentCheckStatusResponse verifyPaymentStatus(User user, String md5Hash) {
        Payment payment = paymentRepository.findByMd5Hash(md5Hash)
                .orElseThrow(() -> new ResourceNotFoundException("Payment not available"));
        requireOwner(user, payment.getAccountNumber());

        if (payment.getStatus() == PaymentStatus.SUCCESS) {
            return new PaymentCheckStatusResponse(md5Hash, PaymentStatus.SUCCESS, true);
        }

        boolean isSuccess = bakongAdapter.checkTransactionByMd5(md5Hash);
        if (isSuccess) {
            payment.setStatus(PaymentStatus.SUCCESS);
            paymentRepository.save(payment);
            return new PaymentCheckStatusResponse(md5Hash, PaymentStatus.SUCCESS, true);
        }

        return new PaymentCheckStatusResponse(md5Hash, payment.getStatus(), false);
    }

    @Override
    @Transactional
    public void processWebhookNotification(BakongWebhookPayload payload) {
        paymentRepository.findByMd5Hash(payload.md5()).ifPresent(payment -> {
            if (payment.getStatus() != PaymentStatus.SUCCESS) {
                payment.setStatus(PaymentStatus.SUCCESS);
                paymentRepository.save(payment);
            }
        });
    }

    private void requireOwner(User user, String accountNumber) {
        var account = accountRepository.findByAccountNumber(accountNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Payment account not available"));
        if (!account.getUser().getId().equals(user.getId()))
            throw new ResourceNotFoundException("Payment account not available");
    }
}
