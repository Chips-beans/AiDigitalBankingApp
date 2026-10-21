package com.bank.digital_banking.module.payment.controller;

import com.bank.digital_banking.module.payment.dto.*;
import com.bank.digital_banking.module.payment.service.BakongService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

// ===================================================================
// Added for Swagger UI categorization & documentation: Bakong Payments
// ===================================================================
@Tag(name = "Bakong Payments", description = "Bakong KHQR payment generation, status verification, and webhook handling")
@RestController
@RequestMapping("/api/v1/payments")
@RequiredArgsConstructor
public class BakongPaymentController {

    private final BakongService bakongService;

    // Added: OpenAPI Operation description
    @Operation(summary = "Generate Bakong KHQR", description = "Generates an EMVCo-compliant KHQR payload for an account or merchant payment")
    @PostMapping("/khqr/generate")
    public ResponseEntity<KhqrGenerateResponse> generateKhqr(
            @org.springframework.security.core.annotation.AuthenticationPrincipal com.bank.digital_banking.module.auth.entity.User user,
            @Valid @RequestBody KhqrGenerateRequest request) {
        KhqrGenerateResponse response = bakongService.generateKhqr(user, request);
        return ResponseEntity.ok(response);
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Verify payment status", description = "Checks whether a Bakong payment with the given MD5 hash has been completed")
    @GetMapping("/verify/{md5Hash}")
    public ResponseEntity<PaymentCheckStatusResponse> verifyPaymentStatus(
            @org.springframework.security.core.annotation.AuthenticationPrincipal com.bank.digital_banking.module.auth.entity.User user,
            @PathVariable String md5Hash) {
        PaymentCheckStatusResponse response = bakongService.verifyPaymentStatus(user, md5Hash);
        return ResponseEntity.ok(response);
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Bakong payment webhook", description = "Receives transaction notification callbacks from the Bakong payment network")
    @PostMapping("/webhook")
    public ResponseEntity<Void> handleBakongWebhook(@RequestBody BakongWebhookPayload payload) {
        bakongService.processWebhookNotification(payload);
        return ResponseEntity.ok().build();
    }
}
