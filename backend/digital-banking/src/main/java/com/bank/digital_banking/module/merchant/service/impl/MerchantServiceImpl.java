package com.bank.digital_banking.module.merchant.service.impl;

import com.bank.digital_banking.module.merchant.dto.*;
import com.bank.digital_banking.module.merchant.entity.Merchant;
import com.bank.digital_banking.module.merchant.entity.MerchantStatus;
import com.bank.digital_banking.module.merchant.repository.MerchantRepository;
import com.bank.digital_banking.module.merchant.service.MerchantService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class MerchantServiceImpl implements MerchantService {

    private final MerchantRepository merchantRepository;

    @Override
    @Transactional
    public MerchantResponse registerMerchant(MerchantRegisterRequest request) {
        if (merchantRepository.existsByBakongAccountId(request.bakongAccountId())) {
            throw new IllegalArgumentException("Bakong account ID is already registered to another merchant");
        }

        String generatedMerchantId = "MCH-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();

        Merchant merchant = Merchant.builder()
                .merchantId(generatedMerchantId)
                .storeName(request.storeName())
                .bakongAccountId(request.bakongAccountId())
                .merchantCity(request.merchantCity())
                .mcc(request.mcc() != null ? request.mcc() : "5999")
                .status(MerchantStatus.PENDING)
                .ownerUserId(request.ownerUserId())
                .build();

        Merchant savedMerchant = merchantRepository.save(merchant);
        return MerchantResponse.fromEntity(savedMerchant);
    }

    @Override
    @Transactional(readOnly = true)
    public MerchantResponse getMerchantById(Long id) {
        Merchant merchant = merchantRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Merchant not found with ID: " + id));
        return MerchantResponse.fromEntity(merchant);
    }

    @Override
    @Transactional(readOnly = true)
    public MerchantResponse getMerchantByMerchantId(String merchantId) {
        Merchant merchant = merchantRepository.findByMerchantId(merchantId)
                .orElseThrow(() -> new RuntimeException("Merchant not found with Merchant ID: " + merchantId));
        return MerchantResponse.fromEntity(merchant);
    }

    @Override
    @Transactional(readOnly = true)
    public List<MerchantResponse> getMerchantsByOwner(Long ownerUserId) {
        return merchantRepository.findByOwnerUserId(ownerUserId)
                .stream()
                .map(MerchantResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<MerchantResponse> getMerchantsByStatus(MerchantStatus status) {
        return merchantRepository.findByStatus(status)
                .stream()
                .map(MerchantResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional
    public MerchantResponse updateMerchant(Long id, MerchantUpdateRequest request) {
        Merchant merchant = merchantRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Merchant not found with ID: " + id));

        if (request.storeName() != null) merchant.setStoreName(request.storeName());
        if (request.merchantCity() != null) merchant.setMerchantCity(request.merchantCity());
        if (request.mcc() != null) merchant.setMcc(request.mcc());
        if (request.status() != null) merchant.setStatus(request.status());

        Merchant updatedMerchant = merchantRepository.save(merchant);
        return MerchantResponse.fromEntity(updatedMerchant);
    }

    @Override
    @Transactional
    public MerchantResponse updateMerchantStatus(Long id, MerchantStatus status) {
        Merchant merchant = merchantRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Merchant not found with ID: " + id));

        merchant.setStatus(status);
        Merchant updatedMerchant = merchantRepository.save(merchant);
        return MerchantResponse.fromEntity(updatedMerchant);
    }
}