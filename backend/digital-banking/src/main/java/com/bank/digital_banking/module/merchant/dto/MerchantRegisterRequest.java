package com.bank.digital_banking.module.merchant.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record MerchantRegisterRequest(
        @NotBlank(message = "Store name is required")
        String storeName,

        @NotBlank(message = "Bakong account ID is required")
        String bakongAccountId,

        @NotBlank(message = "Merchant city is required")
        String merchantCity,

        String mcc,

        @NotNull(message = "Owner user ID is required")
        Long ownerUserId
) {}