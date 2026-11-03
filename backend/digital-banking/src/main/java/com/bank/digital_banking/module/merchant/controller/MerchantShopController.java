package com.bank.digital_banking.module.merchant.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthRateLimiter;
import com.bank.digital_banking.module.merchant.service.MerchantShopService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.UUID;

import static com.bank.digital_banking.module.merchant.dto.MerchantShopDtos.*;

/** Merchant-session-only shop APIs. Owner and shop always come from the session, never the request. */
@RestController @RequestMapping("/api/v1/merchants/me") @RequiredArgsConstructor
@Tag(name = "Merchant shop onboarding")
public class MerchantShopController {
    private final MerchantShopService shops;
    private final MerchantAuthRateLimiter limits;

    private <T> ResponseEntity<ApiResponse<T>> body(HttpStatus status, T value, String message) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(ApiResponse.success(value, message));
    }

    @GetMapping
    @Operation(summary = "Read onboarding state, shop profile and the two business wallets")
    public ResponseEntity<ApiResponse<Profile>> read(@AuthenticationPrincipal User user, Authentication auth) {
        return body(HttpStatus.OK, shops.read(user, (UUID) auth.getDetails()), "Merchant profile");
    }

    @PostMapping("/registration")
    @Operation(summary = "Register the owner's one shop with KHR and USD wallets; Idempotency-Key required")
    public ResponseEntity<ApiResponse<Profile>> register(@AuthenticationPrincipal User user, Authentication auth,
            @RequestHeader("Idempotency-Key") String key, @Valid @RequestBody Registration request) {
        limits.check("shop-register", user.getId().toString(), 10);
        var result = shops.register(user, (UUID) auth.getDetails(), key, request);
        return body(result.created() ? HttpStatus.CREATED : HttpStatus.OK, result.profile(),
                result.created() ? "Shop registered" : "Shop registration already completed");
    }

    @PatchMapping("/profile")
    @Operation(summary = "Edit shop details with the last-read version to prevent lost updates")
    public ResponseEntity<ApiResponse<Profile>> update(@AuthenticationPrincipal User user, Authentication auth,
            @Valid @RequestBody ProfileUpdate request) {
        limits.check("shop-profile", user.getId().toString(), 30);
        return body(HttpStatus.OK, shops.update(user, (UUID) auth.getDetails(), request), "Shop profile updated");
    }

    @PostMapping(value = "/logo-uploads", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @Operation(summary = "Stage a JPG/PNG logo (5 MB, 16 MP); attach it through registration or a profile update")
    public ResponseEntity<ApiResponse<StagedLogo>> upload(@AuthenticationPrincipal User user, Authentication auth,
            @RequestPart("logo") MultipartFile logo) {
        limits.check("shop-logo", user.getId().toString(), 10);
        return body(HttpStatus.CREATED, shops.stageLogo(user, (UUID) auth.getDetails(), logo), "Logo uploaded");
    }

    @GetMapping("/logo")
    @Operation(summary = "Read the attached shop logo image")
    public ResponseEntity<byte[]> logo(@AuthenticationPrincipal User user, Authentication auth) {
        var logo = shops.logo(user, (UUID) auth.getDetails());
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .header("X-Content-Type-Options", "nosniff")
                .contentType(MediaType.parseMediaType(logo.contentType())).body(logo.data());
    }
}
