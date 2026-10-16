package com.bank.digital_banking.module.payment.service;

import com.bank.digital_banking.module.payment.dto.*;

public interface BakongService {
    KhqrGenerateResponse generateKhqr(com.bank.digital_banking.module.auth.entity.User user, KhqrGenerateRequest request);
    PaymentCheckStatusResponse verifyPaymentStatus(com.bank.digital_banking.module.auth.entity.User user, String md5Hash);
    void processWebhookNotification(BakongWebhookPayload payload);
}
