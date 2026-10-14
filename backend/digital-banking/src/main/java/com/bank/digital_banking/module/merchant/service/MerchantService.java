package com.bank.digital_banking.module.merchant.service;

import com.bank.digital_banking.module.merchant.dto.*;
import com.bank.digital_banking.module.merchant.entity.MerchantStatus;

import java.util.List;

public interface MerchantService {
    MerchantResponse registerMerchant(MerchantRegisterRequest request);
    MerchantResponse getMerchantById(Long id);
    MerchantResponse getMerchantByMerchantId(String merchantId);
    List<MerchantResponse> getMerchantsByOwner(Long ownerUserId);
    List<MerchantResponse> getMerchantsByStatus(MerchantStatus status);
    MerchantResponse updateMerchant(Long id, MerchantUpdateRequest request);
    MerchantResponse updateMerchantStatus(Long id, MerchantStatus status);
}