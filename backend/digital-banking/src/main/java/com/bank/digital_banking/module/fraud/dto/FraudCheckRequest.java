package com.bank.digital_banking.module.fraud.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record FraudCheckRequest(
        @NotBlank(message = "Transaction reference is required")
        String transactionRef,

        @NotBlank(message = "Account ID is required")
        String accountId,

        @NotNull(message = "Amount is required")
        @Min(value = 0, message = "Amount must be greater than 0")
        BigDecimal amount,

        @NotBlank(message = "Currency is required")
        String currency,

        String ipAddress,
        String deviceId
) {}