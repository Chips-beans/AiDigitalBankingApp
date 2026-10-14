package com.bank.digital_banking.module.ai.dto;

import com.bank.digital_banking.module.ai.entity.InsightType;

import java.time.LocalDateTime;

public record SpendingInsightResponse(
        Long userId,
        String targetPeriod,
        InsightType insightType,
        String aiAdvice,
        LocalDateTime generatedAt
) {}