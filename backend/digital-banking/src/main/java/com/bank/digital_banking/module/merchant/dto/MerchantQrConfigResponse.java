package com.bank.digital_banking.module.merchant.dto;

import com.bank.digital_banking.module.merchant.entity.Merchant;

public record MerchantQrConfigResponse(
        String merchantId,
        String storeName,
        String merchantAccountId,
        String bakongAccountId, // Alias for backward compatibility
        String merchantCity,
        String mcc,
        String acquiringBank,
        String staticQrString
) {
    public static MerchantQrConfigResponse fromEntity(Merchant merchant, String acquiringBank, String staticQrString) {
        return new MerchantQrConfigResponse(
                merchant.getMerchantId(),
                merchant.getStoreName(),
                merchant.getBakongAccountId(),
                merchant.getBakongAccountId(),
                merchant.getMerchantCity(),
                merchant.getMcc() != null ? merchant.getMcc() : "5999",
                acquiringBank,
                staticQrString
        );
    }
}
