package com.bank.digital_banking.module.ai.dto;

import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.util.List;

public record SpendingInsightRequest(
        @NotNull(message = "User ID is required")
        Long userId,

        @NotNull(message = "Period is required")
        String targetPeriod, // E.g., "2026-10"

        List<CategorySpend> categorySpends
) {
    public record CategorySpend(String category, BigDecimal amount) {}
}