package com.bank.digital_banking.module.payment.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.payment.dto.*;
import com.bank.digital_banking.module.payment.service.QrPaymentService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@Tag(name = "QR Payments", description = "EMVCo-compliant QR code generation, camera scanning, scan-to-transfer, and status verification")
@RestController
@RequestMapping("/api/v1/payments")
@RequiredArgsConstructor
public class QrPaymentController {

    private final QrPaymentService qrPaymentService;

    @Operation(summary = "Generate EMVCo QR code", description = "Generates an EMVCo-compliant QR code payload with all decomposed data needed for client-side rendering")
    @PostMapping("/qr/generate")
    public ResponseEntity<ApiResponse<QrGenerateResponse>> generateQr(
            @AuthenticationPrincipal User user,
            @Valid @RequestBody QrGenerateRequest request) {
        QrGenerateResponse response = qrPaymentService.generateQr(user, request);
        return ResponseEntity.ok(ApiResponse.success(response, "QR code generated successfully"));
    }

    @Operation(summary = "Generate legacy KHQR payload", description = "Backward-compatible endpoint generating an EMVCo QR code string and MD5 hash")
    @PostMapping("/khqr/generate")
    public ResponseEntity<KhqrGenerateResponse> generateKhqr(
            @AuthenticationPrincipal User user,
            @Valid @RequestBody KhqrGenerateRequest request) {
        KhqrGenerateResponse response = qrPaymentService.generateKhqr(user, request);
        return ResponseEntity.ok(response);
    }

    @Operation(summary = "Scan and preview QR code", description = "Decodes a scanned EMVCo QR code string, validates CRC-16, and resolves payee and destination details")
    @PostMapping("/qr/scan")
    public ResponseEntity<ApiResponse<QrScanResponse>> scanQr(
            @AuthenticationPrincipal User user,
            @Valid @RequestBody QrScanRequest request) {
        QrScanResponse response = qrPaymentService.scanQr(user, request);
        return ResponseEntity.ok(ApiResponse.success(response, "QR code scanned and validated successfully"));
    }

    @Operation(summary = "Transfer money by QR scan", description = "Executes an immediate fund transfer using the decoded QR code")
    @PostMapping("/qr/transfer")
    public ResponseEntity<ApiResponse<QrTransferResponse>> transferByQr(
            @AuthenticationPrincipal User user,
            @Parameter(required = true, description = "Required immutable request key; replay with the identical QR payment body")
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Parameter(description = "One-time proof from POST /auth/pin/transfer-proof; not needed to replay a completed key")
            @RequestHeader(value = "X-Pin-Proof", required = false) String pinProof,
            org.springframework.security.core.Authentication authentication,
            @Valid @RequestBody QrTransferRequest request) {
        QrTransferResponse response = qrPaymentService.processQrTransfer(user, idempotencyKey, request,
                new com.bank.digital_banking.module.transaction.service.FinancialCommandService.PinProof(
                        authentication.getDetails() instanceof java.util.UUID session ? session : null, pinProof));
        return ResponseEntity.ok(ApiResponse.success(response, "Transfer by QR completed successfully"));
    }

    @Operation(summary = "Verify payment status", description = "Checks whether a payment with the given MD5 / QR hash has been settled")
    @GetMapping("/verify/{md5Hash}")
    public ResponseEntity<PaymentCheckStatusResponse> verifyPaymentStatus(
            @AuthenticationPrincipal User user,
            @PathVariable String md5Hash) {
        PaymentCheckStatusResponse response = qrPaymentService.verifyPaymentStatus(user, md5Hash);
        return ResponseEntity.ok(response);
    }

    @Operation(summary = "Payment notification webhook", description = "Receives external QR payment settlement notifications")
    @PostMapping("/webhook")
    public ResponseEntity<Void> handleWebhook(@RequestBody QrWebhookPayload payload) {
        qrPaymentService.processWebhookNotification(payload);
        return ResponseEntity.ok().build();
    }
}
