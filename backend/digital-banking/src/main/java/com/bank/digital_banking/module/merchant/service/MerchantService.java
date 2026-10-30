package com.bank.digital_banking.module.merchant.service;

import com.bank.digital_banking.module.merchant.dto.*;
import com.bank.digital_banking.module.merchant.entity.MerchantStatus;
import com.bank.digital_banking.module.auth.entity.User;

import java.util.List;

public interface MerchantService {
    MerchantResponse registerMerchant(User actor, MerchantRegisterRequest request);
    MerchantResponse getMerchantById(User actor, Long id);
    MerchantResponse getMerchantByMerchantId(User actor, String merchantId);
    List<MerchantResponse> getMerchantsByOwner(User actor, Long ownerUserId, int page, int size);
    List<MerchantResponse> getMerchantsByStatus(User actor, MerchantStatus status, int page, int size);
    MerchantResponse updateMerchant(User actor, Long id, MerchantUpdateRequest request);
    MerchantResponse updateMerchantStatus(User actor, Long id, MerchantStatus status);
    List<com.bank.digital_banking.module.account.dto.AccountResponseDto> getMerchantAccounts(User actor, Long merchantId, int page, int size);
    List<com.bank.digital_banking.module.account.dto.AccountResponseDto> getMyMerchantAccounts(User actor, int page, int size);
}
