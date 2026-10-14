package com.bank.digital_banking.module.fraud.dto;

import com.bank.digital_banking.module.fraud.entity.FraudAction;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record FraudRuleRequest(
        @NotBlank(message = "Rule code is required")
        String ruleCode,

        @NotBlank(message = "Rule name is required")
        String ruleName,

        String description,
        BigDecimal thresholdValue,
        Integer velocityLimit,
        Integer windowMinutes,

        @NotNull(message = "Action to take is required")
        FraudAction actionToTake
) {}