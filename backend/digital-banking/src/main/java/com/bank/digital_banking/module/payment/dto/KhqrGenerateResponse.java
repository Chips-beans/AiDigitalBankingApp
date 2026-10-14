package com.bank.digital_banking.module.payment.dto;

public record KhqrGenerateResponse(
        String qrString,
        String md5Hash,
        String accountNumber,
        double amount,
        String currency
) {}