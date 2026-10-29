package com.bank.digital_banking.module.payment.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

import java.math.BigDecimal;

public record KhqrGenerateRequest(
        @NotBlank(message = "Account number is required")
        @Pattern(regexp = "[0-9]{10,20}", message = "Account number must contain 10-20 digits")
        String accountNumber,

        @NotNull(message = "Amount is required")
        @DecimalMin(value = "0", message = "Amount must be greater than or equal to 0")
        BigDecimal amount,

        @NotBlank(message = "Currency is required")
        @Pattern(regexp = "(?i)USD|KHR", message = "Currency must be USD or KHR")
        String currency
) {}
