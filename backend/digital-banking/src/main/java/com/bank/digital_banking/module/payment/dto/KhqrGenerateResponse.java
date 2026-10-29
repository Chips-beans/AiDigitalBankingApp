package com.bank.digital_banking.module.payment.dto;

import java.math.BigDecimal;

public record KhqrGenerateResponse(
        String qrString,
        String md5Hash,
        String accountNumber,
        BigDecimal amount,
        String currency
) {}
