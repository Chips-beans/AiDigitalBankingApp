package com.bank.digital_banking.module.merchant.controller;

import com.bank.digital_banking.module.merchant.dto.*;
import com.bank.digital_banking.module.merchant.entity.MerchantStatus;
import com.bank.digital_banking.module.merchant.service.MerchantService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import com.bank.digital_banking.module.auth.entity.User;

import java.util.List;

@RestController
@RequestMapping("/api/v1/merchants")
@RequiredArgsConstructor
public class MerchantController {

    private final MerchantService merchantService;

    @PostMapping("/register")
    public ResponseEntity<MerchantResponse> registerMerchant(@AuthenticationPrincipal User actor, @Valid @RequestBody MerchantRegisterRequest request) {
        MerchantResponse response = merchantService.registerMerchant(actor, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<MerchantResponse> getMerchantById(@AuthenticationPrincipal User actor, @PathVariable Long id) {
        return ResponseEntity.ok(merchantService.getMerchantById(actor, id));
    }

    @GetMapping("/code/{merchantId}")
    public ResponseEntity<MerchantResponse> getMerchantByMerchantId(@AuthenticationPrincipal User actor, @PathVariable String merchantId) {
        return ResponseEntity.ok(merchantService.getMerchantByMerchantId(actor, merchantId));
    }

    @GetMapping("/owner/{ownerUserId}")
    public ResponseEntity<List<MerchantResponse>> getMerchantsByOwner(@AuthenticationPrincipal User actor, @PathVariable Long ownerUserId, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(merchantService.getMerchantsByOwner(actor, ownerUserId, page, size));
    }

    @GetMapping("/status/{status}")
    public ResponseEntity<List<MerchantResponse>> getMerchantsByStatus(@AuthenticationPrincipal User actor, @PathVariable MerchantStatus status, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(merchantService.getMerchantsByStatus(actor, status, page, size));
    }

    @PutMapping("/{id}")
    public ResponseEntity<MerchantResponse> updateMerchant(@AuthenticationPrincipal User actor, @PathVariable Long id, @Valid @RequestBody MerchantUpdateRequest request) {
        return ResponseEntity.ok(merchantService.updateMerchant(actor, id, request));
    }

    @PatchMapping("/{id}/status")
    public ResponseEntity<MerchantResponse> updateMerchantStatus(@AuthenticationPrincipal User actor, @PathVariable Long id, @RequestParam MerchantStatus status) {
        return ResponseEntity.ok(merchantService.updateMerchantStatus(actor, id, status));
    }
    
    @GetMapping("/{id}/khqr-config")
    public ResponseEntity<MerchantKhqrConfigResponse> getMerchantKhqrConfig(@AuthenticationPrincipal User actor, @PathVariable Long id) {
        MerchantResponse merchant = merchantService.getMerchantById(actor, id);
        
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
