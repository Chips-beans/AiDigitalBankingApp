package com.bank.digital_banking.module.merchant.controller;

import com.bank.digital_banking.module.merchant.dto.*;
import com.bank.digital_banking.module.merchant.entity.MerchantStatus;
import com.bank.digital_banking.module.merchant.service.MerchantService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/merchants")
@RequiredArgsConstructor
public class MerchantController {

    private final MerchantService merchantService;

    @PostMapping("/register")
    public ResponseEntity<MerchantResponse> registerMerchant(@Valid @RequestBody MerchantRegisterRequest request) {
        MerchantResponse response = merchantService.registerMerchant(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<MerchantResponse> getMerchantById(@PathVariable Long id) {
        return ResponseEntity.ok(merchantService.getMerchantById(id));
    }

    @GetMapping("/code/{merchantId}")
    public ResponseEntity<MerchantResponse> getMerchantByMerchantId(@PathVariable String merchantId) {
        return ResponseEntity.ok(merchantService.getMerchantByMerchantId(merchantId));
    }

    @GetMapping("/owner/{ownerUserId}")
    public ResponseEntity<List<MerchantResponse>> getMerchantsByOwner(@PathVariable Long ownerUserId) {
        return ResponseEntity.ok(merchantService.getMerchantsByOwner(ownerUserId));
    }

    @GetMapping("/status/{status}")
    public ResponseEntity<List<MerchantResponse>> getMerchantsByStatus(@PathVariable MerchantStatus status) {
        return ResponseEntity.ok(merchantService.getMerchantsByStatus(status));
    }

    @PutMapping("/{id}")
    public ResponseEntity<MerchantResponse> updateMerchant(@PathVariable Long id, @RequestBody MerchantUpdateRequest request) {
        return ResponseEntity.ok(merchantService.updateMerchant(id, request));
    }

    @PatchMapping("/{id}/status")
    public ResponseEntity<MerchantResponse> updateMerchantStatus(@PathVariable Long id, @RequestParam MerchantStatus status) {
        return ResponseEntity.ok(merchantService.updateMerchantStatus(id, status));
    }
    
    @GetMapping("/{id}/khqr-config")
    public ResponseEntity<MerchantKhqrConfigResponse> getMerchantKhqrConfig(@PathVariable Long id) {
        MerchantResponse merchant = merchantService.getMerchantById(id);
        
        MerchantKhqrConfigResponse response = new MerchantKhqrConfigResponse(
                merchant.merchantId(),
                merchant.storeName(),
                merchant.bakongAccountId(),
                merchant.merchantCity(),
                merchant.mcc(),
                "Digital Bank" // Acquiring Bank Name
        );
        
        return ResponseEntity.ok(response);
    }
}