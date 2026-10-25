package com.bank.digital_banking.module.payment.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

import java.math.BigDecimal;

public record QrGenerateRequest(
        @NotBlank(message = "Account number is required")
        @Pattern(regexp = "[0-9]{10,20}", message = "Account number must contain 10-20 digits")
        String accountNumber,

        BigDecimal amount,

        @NotBlank(message = "Currency is required")
        @Pattern(regexp = "(?i)USD|KHR", message = "Currency must be USD or KHR")
        String currency,

        String remark,

        String billNumber,

        String qrType // "STATIC" or "DYNAMIC"
) {}
