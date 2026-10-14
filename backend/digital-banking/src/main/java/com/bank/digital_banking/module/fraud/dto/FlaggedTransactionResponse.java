package com.bank.digital_banking.module.fraud.dto;

import com.bank.digital_banking.module.fraud.entity.FlaggedTransaction;
import com.bank.digital_banking.module.fraud.entity.FraudAction;
import com.bank.digital_banking.module.fraud.entity.RiskLevel;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record FlaggedTransactionResponse(
        Long id,
        String transactionRef,
        String accountId,
        BigDecimal amount,
        String currency,
        String triggeredRuleCode,
        String reason,
        RiskLevel riskLevel,
        FraudAction actionTaken,
        LocalDateTime createdAt
) {
    public static FlaggedTransactionResponse fromEntity(FlaggedTransaction entity) {
        return new FlaggedTransactionResponse(
                entity.getId(),
                entity.getTransactionRef(),
                entity.getAccountId(),
                entity.getAmount(),
                entity.getCurrency(),
                entity.getTriggeredRuleCode(),
                entity.getReason(),
                entity.getRiskLevel(),
                entity.getActionTaken(),
                entity.getCreatedAt()
        );
    }
}