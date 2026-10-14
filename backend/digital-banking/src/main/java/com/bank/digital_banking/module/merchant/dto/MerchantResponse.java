package com.bank.digital_banking.module.merchant.dto;

import com.bank.digital_banking.module.merchant.entity.Merchant;
import com.bank.digital_banking.module.merchant.entity.MerchantStatus;

import java.time.LocalDateTime;

public record MerchantResponse(
        Long id,
        String merchantId,
        String storeName,
        String bakongAccountId,
        String merchantCity,
        String mcc,
        MerchantStatus status,
        Long ownerUserId,
        LocalDateTime createdAt
) {
    public static MerchantResponse fromEntity(Merchant merchant) {
        return new MerchantResponse(
                merchant.getId(),
                merchant.getMerchantId(),
                merchant.getStoreName(),
                merchant.getBakongAccountId(),
                merchant.getMerchantCity(),
                merchant.getMcc(),
                merchant.getStatus(),
                merchant.getOwnerUserId(),
                merchant.getCreatedAt()
        );
    }
}