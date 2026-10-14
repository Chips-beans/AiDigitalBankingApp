package com.bank.digital_banking.module.fraud.dto;

import com.bank.digital_banking.module.fraud.entity.FraudAction;
import com.bank.digital_banking.module.fraud.entity.RiskLevel;

public record FraudCheckResponse(
        String transactionRef,
        RiskLevel riskLevel,
        FraudAction action,
        String reason,
        boolean allowed
) {}