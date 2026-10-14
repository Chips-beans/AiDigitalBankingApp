package com.bank.digital_banking.module.payment.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;

public record BakongWebhookPayload(
        @JsonProperty("md5") String md5,
        @JsonProperty("fromAccountId") String fromAccountId,
        @JsonProperty("toAccountId") String toAccountId,
        @JsonProperty("amount") BigDecimal amount,
        @JsonProperty("currency") String currency,
        @JsonProperty("description") String description
) {}
