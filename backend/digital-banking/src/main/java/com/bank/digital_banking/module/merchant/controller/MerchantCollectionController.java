package com.bank.digital_banking.module.merchant.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthRateLimiter;
import com.bank.digital_banking.module.merchant.service.MerchantCollectionService;
import com.bank.digital_banking.module.merchant.service.MerchantShopService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

import static com.bank.digital_banking.module.merchant.dto.MerchantCollectionDtos.*;

/** M5 dashboard/wallets and M6 QR collection. Shop and wallets always come from the Merchant session. */
@RestController @RequestMapping("/api/v1") @RequiredArgsConstructor
@Tag(name = "Merchant dashboard and collection")
public class MerchantCollectionController {
    private final MerchantCollectionService collections;
    private final MerchantShopService shops;
    private final MerchantAuthRateLimiter limits;

    private <T> ResponseEntity<ApiResponse<T>> body(HttpStatus status, T value, String message) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(ApiResponse.success(value, message));
    }
    private static UUID sid(Authentication auth) { return (UUID) auth.getDetails(); }

    @GetMapping("/merchants/me/dashboard")
    @Operation(summary = "Shop, separate KHR/USD balances, today's collections and recent payments")
    public ResponseEntity<ApiResponse<Dashboard>> dashboard(@AuthenticationPrincipal User user, Authentication auth) {
        return body(HttpStatus.OK, collections.dashboard(user, sid(auth)), "Merchant dashboard");
    }

    @GetMapping("/merchants/me/wallets/{accountNumber}")
    @Operation(summary = "One business wallet with read-only activity, 20 per page")
    public ResponseEntity<ApiResponse<WalletDetail>> wallet(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable String accountNumber, @RequestParam(defaultValue = "0") int page) {
        return body(HttpStatus.OK, collections.wallet(user, sid(auth), accountNumber, page), "Business wallet");
    }

    @GetMapping("/merchants/me/qr")
    @Operation(summary = "The shop's reusable QR for one currency (customers enter the amount)")
    public ResponseEntity<ApiResponse<ShopQr>> qr(@AuthenticationPrincipal User user, Authentication auth,
            @RequestParam String currency) {
        return body(HttpStatus.OK, collections.staticQr(user, sid(auth), currency), "Shop QR");
    }

    @PostMapping("/merchants/me/payment-requests")
    @Operation(summary = "Create a fixed-amount QR request; Idempotency-Key required; expires after a few minutes")
    public ResponseEntity<ApiResponse<PaymentRequestView>> create(@AuthenticationPrincipal User user, Authentication auth,
            @RequestHeader("Idempotency-Key") String key, @Valid @RequestBody NewPaymentRequest request) {
        limits.check("shop-request", user.getId().toString(), 60);
        var result = collections.create(user, sid(auth), key, request);
        return body(result.created() ? HttpStatus.CREATED : HttpStatus.OK, result.request(), "Payment request");
    }

    @GetMapping("/merchants/me/payment-requests/{id}")
    @Operation(summary = "WAITING, PAID (with confirmed receipt), EXPIRED or CANCELLED, plus server time")
    public ResponseEntity<ApiResponse<PaymentRequestView>> status(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id) {
        limits.check("shop-poll", user.getId().toString(), 120);
        return body(HttpStatus.OK, collections.status(user, sid(auth), id), "Payment request");
    }

    @PostMapping("/merchants/me/payment-requests/{id}/cancel")
    @Operation(summary = "Cancel a waiting request; an already paid request is returned as PAID")
    public ResponseEntity<ApiResponse<PaymentRequestView>> cancel(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id) {
        return body(HttpStatus.OK, collections.cancel(user, sid(auth), id), "Payment request");
    }

    @GetMapping("/payments/merchants/{merchantId}/logo")
    @Operation(summary = "Customer payment preview: an active shop's logo (same shape as recipient photos)")
    public ResponseEntity<ApiResponse<com.bank.digital_banking.module.auth.service.ProfilePhotoService.Photo>> previewLogo(
            @PathVariable String merchantId) {
        var logo = shops.paymentPreviewLogo(merchantId);
        return body(HttpStatus.OK, new com.bank.digital_banking.module.auth.service.ProfilePhotoService.Photo(
                logo.contentType(), java.util.Base64.getEncoder().encodeToString(logo.data())), "Shop logo");
    }
}
