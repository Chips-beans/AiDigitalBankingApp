package com.bank.digital_banking.module.payment.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record KhqrGenerateRequest(
        @NotBlank(message = "Account number is required")
        String accountNumber,

        @NotNull(message = "Amount is required")
        @Min(value = 0, message = "Amount must be greater than or equal to 0")
        BigDecimal amount,

        @NotBlank(message = "Currency must be USD or KHR")
        String currency
) {}