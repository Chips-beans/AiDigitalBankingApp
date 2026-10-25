package com.bank.digital_banking.module.merchant.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record MerchantRegisterRequest(
        @NotBlank(message = "Store name is required")
        String storeName,

        @NotBlank(message = "Merchant QR account ID is required (e.g. store_name@digitalbank)")
        @JsonAlias("bakongAccountId")  // accept old field name from legacy clients
        String merchantAccountId,

        @NotBlank(message = "Merchant city is required")
        String merchantCity,

        String mcc,

        @NotNull(message = "Owner user ID is required")
        Long ownerUserId
) {}
