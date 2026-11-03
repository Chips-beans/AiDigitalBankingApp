package com.bank.digital_banking.module.merchant.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthDtos;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthRateLimiter;
import com.bank.digital_banking.module.merchant.service.MerchantOwnerTransferService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

import static com.bank.digital_banking.module.merchant.dto.MerchantOwnerTransferDtos.*;

/**
 * M8 owner transfers. The Merchant session creates, watches and cancels an intent; only a fresh-PIN
 * approval in the Customer App moves money. The destination is chosen by the server.
 */
@RestController @RequestMapping("/api/v1") @RequiredArgsConstructor
@Tag(name = "Merchant owner transfers")
public class MerchantOwnerTransferController {
    private final MerchantOwnerTransferService transfers;
    private final MerchantAuthRateLimiter limits;

    private <T> ResponseEntity<ApiResponse<T>> body(HttpStatus status, T value, String message) {
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).body(ApiResponse.success(value, message));
    }
    private static UUID sid(Authentication auth) { return (UUID) auth.getDetails(); }

    @PostMapping("/merchants/me/owner-transfers")
    @Operation(summary = "Create a transfer from a business wallet to the owner's own wallet; Idempotency-Key required; approval happens in Kesor Bank")
    public ResponseEntity<ApiResponse<TransferView>> create(@AuthenticationPrincipal User user, Authentication auth,
            @RequestHeader("Idempotency-Key") String key, @Valid @RequestBody NewOwnerTransfer request) {
        limits.check("owner-transfer", user.getId().toString(), 20);
        var result = transfers.create(user, sid(auth), key, request);
        return body(result.created() ? HttpStatus.CREATED : HttpStatus.OK, result.transfer(), "Owner transfer");
    }

    @GetMapping("/merchants/me/owner-transfers/{id}")
    @Operation(summary = "PENDING, COMPLETED (with receipt), DENIED, CANCELLED, EXPIRED or FAILED, plus server time")
    public ResponseEntity<ApiResponse<TransferView>> status(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id) {
        limits.check("owner-xfer-poll", user.getId().toString(), 120);
        return body(HttpStatus.OK, transfers.status(user, sid(auth), id), "Owner transfer");
    }

    @PostMapping("/merchants/me/owner-transfers/{id}/cancel")
    @Operation(summary = "Cancel a waiting transfer; an already completed transfer is returned as COMPLETED")
    public ResponseEntity<ApiResponse<TransferView>> cancel(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id) {
        return body(HttpStatus.OK, transfers.cancel(user, sid(auth), id), "Owner transfer");
    }

    @GetMapping("/merchant-transfers/{id}")
    @Operation(summary = "Customer views the exact transfer using its private handoff token")
    public ResponseEntity<ApiResponse<TransferDetails>> details(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id, @RequestHeader("X-Merchant-Handoff") String handoff, HttpServletRequest http) {
        limits.check("ip", http.getRemoteAddr(), 120); limits.check("customer", user.getId().toString(), 30);
        if (!handoff.matches("[A-Za-z0-9_-]{43}")) throw new IllegalArgumentException();
        return body(HttpStatus.OK, transfers.details(user, sid(auth), id, handoff), "Owner transfer");
    }

    @PostMapping("/merchant-transfers/{id}/approve")
    @Operation(summary = "Customer approves with fresh PIN digits; approval posts the transfer atomically")
    public ResponseEntity<ApiResponse<TransferOutcome>> approve(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id, @Valid @RequestBody MerchantAuthDtos.Approve request, HttpServletRequest http) {
        limits.check("ip", http.getRemoteAddr(), 120); limits.check("customer", user.getId().toString(), 30);
        return body(HttpStatus.OK, transfers.approve(user, sid(auth), id, request), "Owner transfer");
    }

    @PostMapping("/merchant-transfers/{id}/deny")
    @Operation(summary = "Customer declines a pending transfer; no money moves")
    public ResponseEntity<ApiResponse<TransferOutcome>> deny(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id, @Valid @RequestBody MerchantAuthDtos.Handoff request, HttpServletRequest http) {
        limits.check("ip", http.getRemoteAddr(), 120); limits.check("customer", user.getId().toString(), 30);
        return body(HttpStatus.OK, transfers.deny(user, sid(auth), id, request), "Owner transfer");
    }
}
