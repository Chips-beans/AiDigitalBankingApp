package com.bank.digital_banking.module.merchant.service.impl;

import com.bank.digital_banking.common.util.PageBounds;

import com.bank.digital_banking.module.audit.service.AuditTrail;

import com.bank.digital_banking.module.merchant.dto.*;
import com.bank.digital_banking.module.merchant.entity.Merchant;
import com.bank.digital_banking.module.merchant.entity.MerchantStatus;
import com.bank.digital_banking.module.merchant.repository.MerchantRepository;
import com.bank.digital_banking.module.merchant.service.MerchantService;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.entity.ERole;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import org.springframework.security.access.AccessDeniedException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class MerchantServiceImpl implements MerchantService {

    private final MerchantRepository merchantRepository;
    private final AuditTrail audit;

    @Override
    @Transactional
    public MerchantResponse registerMerchant(User actor, MerchantRegisterRequest request) {
        if (!isAdmin(actor) && !actor.getId().equals(request.ownerUserId())) {
            throw new AccessDeniedException("Cannot register a merchant for another user");
        }
        if (merchantRepository.existsByBakongAccountId(request.merchantAccountId())) {
            throw new IllegalArgumentException("Merchant QR account ID is already registered to another merchant");
        }

        String generatedMerchantId = "MCH-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();

        Merchant merchant = Merchant.builder()
                .merchantId(generatedMerchantId)
                .storeName(request.storeName())
                .bakongAccountId(request.merchantAccountId())
                .merchantCity(request.merchantCity())
                .mcc(request.mcc() != null ? request.mcc() : "5999")
                .status(MerchantStatus.PENDING)
                .ownerUserId(request.ownerUserId())
                .build();

        Merchant savedMerchant = merchantRepository.save(merchant);
        audit.successAs(actor, "MERCHANT", "MERCHANT_REGISTERED", savedMerchant.getId().toString());
        return MerchantResponse.fromEntity(savedMerchant);
    }

    @Override
    @Transactional(readOnly = true)
    public MerchantResponse getMerchantById(User actor, Long id) {
        Merchant merchant = merchantRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Merchant not available"));
        requireOwner(actor, merchant);
        return MerchantResponse.fromEntity(merchant);
    }

    @Override
    @Transactional(readOnly = true)
    public MerchantResponse getMerchantByMerchantId(User actor, String merchantId) {
        Merchant merchant = merchantRepository.findByMerchantId(merchantId)
                .orElseThrow(() -> new ResourceNotFoundException("Merchant not available"));
        requireOwner(actor, merchant);
        return MerchantResponse.fromEntity(merchant);
    }

    @Override
    @Transactional(readOnly = true)
    public List<MerchantResponse> getMerchantsByOwner(User actor, Long ownerUserId, int page, int size) {
        if (!isAdmin(actor) && !actor.getId().equals(ownerUserId)) {
            throw new ResourceNotFoundException("Merchant not available");
        }
        return merchantRepository.findByOwnerUserId(ownerUserId, PageBounds.ascendingId(page, size))
                .stream()
                .map(MerchantResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<MerchantResponse> getMerchantsByStatus(User actor, MerchantStatus status, int page, int size) {
        requireAdmin(actor);
        return merchantRepository.findByStatus(status, PageBounds.ascendingId(page, size))
                .stream()
                .map(MerchantResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional
    public MerchantResponse updateMerchant(User actor, Long id, MerchantUpdateRequest request) {
        // Serialize detail edits with administrative status changes to prevent stale overwrites.
        Merchant merchant = merchantRepository.findLockedById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Merchant not available"));
        requireOwner(actor, merchant);
        if (request.status() != null) requireAdmin(actor);

        if (request.storeName() != null) merchant.setStoreName(request.storeName());
        if (request.merchantCity() != null) merchant.setMerchantCity(request.merchantCity());
        if (request.mcc() != null) merchant.setMcc(request.mcc());
        if (request.status() != null) merchant.setStatus(request.status());

        Merchant updatedMerchant = merchantRepository.save(merchant);
        audit.successAs(actor, "MERCHANT", "MERCHANT_UPDATED", updatedMerchant.getId().toString());
        return MerchantResponse.fromEntity(updatedMerchant);
    }

    @Override
    @Transactional
    public MerchantResponse updateMerchantStatus(User actor, Long id, MerchantStatus status) {
        requireAdmin(actor);
        Merchant merchant = merchantRepository.findLockedById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Merchant not available"));

        merchant.setStatus(status);
        Merchant updatedMerchant = merchantRepository.save(merchant);
        audit.successAs(actor, "MERCHANT", "MERCHANT_STATUS_CHANGED", updatedMerchant.getId().toString());
        return MerchantResponse.fromEntity(updatedMerchant);
    }

    private boolean isAdmin(User actor) {
        return actor.getRoles().stream().anyMatch(role -> role.getName() == ERole.ROLE_ADMIN);
    }

    private void requireAdmin(User actor) {
        if (!isAdmin(actor)) throw new AccessDeniedException("Merchant approval requires an administrator");
    }

    private void requireOwner(User actor, Merchant merchant) {
        if (!isAdmin(actor) && !merchant.getOwnerUserId().equals(actor.getId())) {
            throw new ResourceNotFoundException("Merchant not available");
        }
    }
}
