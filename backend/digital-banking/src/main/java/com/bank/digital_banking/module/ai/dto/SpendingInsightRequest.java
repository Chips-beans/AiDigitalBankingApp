package com.bank.digital_banking.module.ai.dto;

import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.util.List;

public record SpendingInsightRequest(
        @NotNull(message = "User ID is required")
        Long userId,

        @NotNull(message = "Period is required")
        @jakarta.validation.constraints.Size(max=20)
        String targetPeriod, // E.g., "2026-10"

        @jakarta.validation.constraints.Size(max=50)
        List<@jakarta.validation.constraints.NotNull @jakarta.validation.Valid CategorySpend> categorySpends
) {
    public record CategorySpend(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max=80) String category,
            @NotNull @jakarta.validation.constraints.DecimalMin("0") @jakarta.validation.constraints.Digits(integer=13,fraction=2) BigDecimal amount) {}
}
