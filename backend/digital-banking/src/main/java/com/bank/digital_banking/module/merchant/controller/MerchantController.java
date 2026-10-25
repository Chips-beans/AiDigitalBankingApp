package com.bank.digital_banking.module.merchant.controller;

import com.bank.digital_banking.module.merchant.dto.*;
import com.bank.digital_banking.module.merchant.entity.MerchantStatus;
import com.bank.digital_banking.module.merchant.service.MerchantService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import com.bank.digital_banking.module.auth.entity.User;

import java.util.List;

// ===================================================================
// Added for Swagger UI categorization & documentation: Merchants
// ===================================================================
@Tag(name = "Merchants", description = "Merchant onboarding, profile lifecycle, and QR merchant configuration")
@RestController
@RequestMapping("/api/v1/merchants")
@RequiredArgsConstructor
public class MerchantController {

    private final MerchantService merchantService;
    private final com.bank.digital_banking.module.payment.qr.QrCodeEngine qrCodeEngine;

    // Added: OpenAPI Operation description
    @Operation(summary = "Register merchant", description = "Creates a new merchant profile for the authenticated user")
    @PostMapping("/register")
    public ResponseEntity<MerchantResponse> registerMerchant(@AuthenticationPrincipal User actor, @Valid @RequestBody MerchantRegisterRequest request) {
        MerchantResponse response = merchantService.registerMerchant(actor, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Get merchant by ID", description = "Retrieves merchant details by database ID")
    @GetMapping("/{id}")
    public ResponseEntity<MerchantResponse> getMerchantById(@AuthenticationPrincipal User actor, @PathVariable Long id) {
        return ResponseEntity.ok(merchantService.getMerchantById(actor, id));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Get merchant by merchant code", description = "Retrieves merchant details by unique merchant code")
    @GetMapping("/code/{merchantId}")
    public ResponseEntity<MerchantResponse> getMerchantByMerchantId(@AuthenticationPrincipal User actor, @PathVariable String merchantId) {
        return ResponseEntity.ok(merchantService.getMerchantByMerchantId(actor, merchantId));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "List merchants by owner", description = "Retrieves merchants owned by the specified user ID")
    @GetMapping("/owner/{ownerUserId}")
    public ResponseEntity<List<MerchantResponse>> getMerchantsByOwner(@AuthenticationPrincipal User actor, @PathVariable Long ownerUserId, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(merchantService.getMerchantsByOwner(actor, ownerUserId, page, size));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "List merchants by status", description = "Retrieves merchants filtered by status (PENDING, APPROVED, REJECTED, SUSPENDED)")
    @GetMapping("/status/{status}")
    public ResponseEntity<List<MerchantResponse>> getMerchantsByStatus(@AuthenticationPrincipal User actor, @PathVariable MerchantStatus status, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(merchantService.getMerchantsByStatus(actor, status, page, size));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Update merchant", description = "Updates details of an existing merchant profile")
    @PutMapping("/{id}")
    public ResponseEntity<MerchantResponse> updateMerchant(@AuthenticationPrincipal User actor, @PathVariable Long id, @Valid @RequestBody MerchantUpdateRequest request) {
        return ResponseEntity.ok(merchantService.updateMerchant(actor, id, request));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Update merchant status", description = "Updates merchant approval or suspension status")
    @PatchMapping("/{id}/status")
    public ResponseEntity<MerchantResponse> updateMerchantStatus(@AuthenticationPrincipal User actor, @PathVariable Long id, @RequestParam MerchantStatus status) {
        return ResponseEntity.ok(merchantService.updateMerchantStatus(actor, id, status));
    }
    
    // Added: OpenAPI Operation description
    @Operation(summary = "Get merchant QR configuration", description = "Retrieves QR credentials, merchant account details, and pre-computed static QR code for this merchant")
    @GetMapping(value = {"/{id}/qr-config", "/{id}/khqr-config"})
    public ResponseEntity<MerchantQrConfigResponse> getMerchantQrConfig(@AuthenticationPrincipal User actor, @PathVariable Long id) {
        MerchantResponse merchant = merchantService.getMerchantById(actor, id);
        
        String staticQr = null;
        try {
            var qr = qrCodeEngine.generate(new com.bank.digital_banking.module.payment.qr.QrCodeEngine.GenerateOptions(
                    merchant.merchantAccountId(),
                    merchant.storeName(),
                    null,
                    "USD",
                    "Payment to " + merchant.storeName(),
                    null,
                    merchant.merchantId(),
                    false
            ));
            staticQr = qr.getQrString();
        } catch (Exception ignored) {}

        MerchantQrConfigResponse response = new MerchantQrConfigResponse(
                merchant.merchantId(),
                merchant.storeName(),
                merchant.merchantAccountId(),
                merchant.merchantAccountId(),
                merchant.merchantCity(),
                merchant.mcc() != null ? merchant.mcc() : "5999",
                "Digital Bank",
                staticQr
        );
        
        return ResponseEntity.ok(response);
    }
}
