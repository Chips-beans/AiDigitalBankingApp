package com.bank.digital_banking.module.payment.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;

/**
 * Generic QR payment settlement notification webhook payload.
 * The {@code md5} field carries the QR hash (MD5 of the QR string)
 * used to look up and settle the matching payment record.
 */
public record QrWebhookPayload(
        @JsonProperty("md5") String md5,
        @JsonProperty("fromAccountId") String fromAccountId,
        @JsonProperty("toAccountId") String toAccountId,
        @JsonProperty("amount") BigDecimal amount,
        @JsonProperty("currency") String currency,
        @JsonProperty("description") String description
) {}
