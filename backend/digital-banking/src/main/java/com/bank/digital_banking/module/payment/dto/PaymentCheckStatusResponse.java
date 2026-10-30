package com.bank.digital_banking.module.payment.dto;

import com.bank.digital_banking.module.payment.entity.PaymentStatus;

public record PaymentCheckStatusResponse(
        String md5Hash,
        PaymentStatus status,
        boolean isPaid
) {
    // Keep the legacy flat fields while supporting the shared customer API client.
    public boolean isSuccess() { return true; }
}
