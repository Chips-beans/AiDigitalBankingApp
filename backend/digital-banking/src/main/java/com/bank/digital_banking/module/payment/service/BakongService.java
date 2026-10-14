package com.bank.digital_banking.module.payment.service;

import com.bank.digital_banking.module.payment.dto.*;

public interface BakongService {
    KhqrGenerateResponse generateKhqr(KhqrGenerateRequest request);
    PaymentCheckStatusResponse verifyPaymentStatus(String md5Hash);
    void processWebhookNotification(BakongWebhookPayload payload);
}