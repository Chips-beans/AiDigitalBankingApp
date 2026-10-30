package com.bank.digital_banking.module.payment.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

import java.math.BigDecimal;

public record QrTransferRequest(
        @NotBlank(message = "Source account number is required")
        @Pattern(regexp = "[0-9]{10,20}", message = "Account number must contain 10-20 digits")
        String sourceAccountNumber,

        @NotBlank(message = "QR code string is required")
        @jakarta.validation.constraints.Size(max = 4096)
        String qrString,

        BigDecimal amount,

        String currency,

        @jakarta.validation.constraints.Size(max = 255) String remark
) {}
