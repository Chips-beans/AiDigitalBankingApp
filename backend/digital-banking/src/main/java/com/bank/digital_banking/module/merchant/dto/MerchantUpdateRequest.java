package com.bank.digital_banking.module.merchant.dto;

import com.bank.digital_banking.module.merchant.entity.MerchantStatus;

public record MerchantUpdateRequest(
        String storeName,
        String merchantCity,
        String mcc,
        MerchantStatus status
) {}