package com.bank.digital_banking.module.merchant.dto;

import com.bank.digital_banking.module.merchant.entity.Merchant;

public record MerchantKhqrConfigResponse(
        String merchantId,
        String storeName,
        String bakongAccountId,
        String merchantCity,
        String mcc,
        String acquiringBank
) {
    public static MerchantKhqrConfigResponse fromEntity(Merchant merchant, String acquiringBank) {
        return new MerchantKhqrConfigResponse(
                merchant.getMerchantId(),
                merchant.getStoreName(),
                merchant.getBakongAccountId(),
                merchant.getMerchantCity(),
                merchant.getMcc() != null ? merchant.getMcc() : "5999",
                acquiringBank
        );
    }
}