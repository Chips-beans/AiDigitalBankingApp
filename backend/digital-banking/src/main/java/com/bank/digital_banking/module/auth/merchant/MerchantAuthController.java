package com.bank.digital_banking.module.auth.merchant;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.dto.TokenResponseDto;
import com.bank.digital_banking.module.auth.entity.User;
import io.swagger.v3.oas.annotations.security.SecurityRequirements;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import io.swagger.v3.oas.annotations.responses.*;
import io.swagger.v3.oas.annotations.media.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.*;
import static com.bank.digital_banking.module.auth.merchant.MerchantAuthDtos.*;

@RestController @RequestMapping("/api/v1") @RequiredArgsConstructor
@Tag(name="Merchant approval and sessions")
@ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(responseCode="400",description="Invalid or malformed credentials",content=@Content(schema=@Schema(implementation=com.bank.digital_banking.common.dto.ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(responseCode="401",description="Missing, invalid, expired or revoked session"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(responseCode="403",description="Wrong application purpose, locked PIN or invalid PIN"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(responseCode="409",description="Expired, denied, cancelled or consumed attempt"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(responseCode="429",description="Persistent rate budget exhausted; Retry-After header"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(responseCode="503",description="Merchant sign-in or required audit storage unavailable")
})
public class MerchantAuthController {
    private final MerchantAuthService service;
    private final MerchantAuthRateLimiter limits;
    private void budget(HttpServletRequest http) { limits.check("ip",http.getRemoteAddr(),120); }
    private <T> ResponseEntity<ApiResponse<T>> ok(T value) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(ApiResponse.success(value,"Merchant sign-in"));
    }
    @PostMapping("/merchant-auth/attempts") @SecurityRequirements
    @Operation(summary="Start a two-minute S256-bound approval attempt")
    public ResponseEntity<ApiResponse<Started>> start(@Valid @RequestBody Start request, HttpServletRequest http) {
        budget(http); limits.check("start-ip",http.getRemoteAddr(),20); limits.check("start-install",request.installationId(),10);
        return ok(service.start(request));
    }
    @GetMapping("/merchant-auth/attempts/{id}")
    @Operation(summary="Customer views a sign-in request using its private handoff token")
    public ResponseEntity<ApiResponse<Details>> details(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id, @RequestHeader("X-Merchant-Handoff") String handoff, HttpServletRequest http) {
        budget(http); limits.check("customer",user.getId().toString(),30);
        if (!handoff.matches("[A-Za-z0-9_-]{43}")) throw new IllegalArgumentException();
        return ok(service.details(user,(UUID)auth.getDetails(),id,handoff));
    }
    @PostMapping("/merchant-auth/attempts/{id}/approve")
    @Operation(summary="Customer explicitly approves with fresh PIN digits")
    public ResponseEntity<ApiResponse<Callback>> approve(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id, @Valid @RequestBody Approve request, HttpServletRequest http) {
        budget(http); limits.check("customer",user.getId().toString(),30);
        return ok(service.approve(user,(UUID)auth.getDetails(),id,request));
    }
    @PostMapping("/merchant-auth/attempts/{id}/deny")
    @Operation(summary="Customer denies a pending sign-in")
    public ResponseEntity<ApiResponse<Callback>> deny(@AuthenticationPrincipal User user, Authentication auth,
            @PathVariable UUID id, @Valid @RequestBody Handoff request, HttpServletRequest http) {
        budget(http); limits.check("customer",user.getId().toString(),30);
        return ok(service.deny(user,(UUID)auth.getDetails(),id,request));
    }
    @PostMapping("/merchant-auth/attempts/{id}/status") @SecurityRequirements
    @Operation(summary="Read minimal attempt status using the private attempt secret")
    public ResponseEntity<ApiResponse<Status>> status(@PathVariable UUID id, @Valid @RequestBody Secret request, HttpServletRequest http) {
        budget(http); limits.check("status",id.toString(),40);
        return ok(service.status(id,request));
    }
    @PostMapping("/merchant-auth/attempts/{id}/cancel") @SecurityRequirements
    @Operation(summary="Cancel the attempt and revoke any derived Merchant session")
    public ResponseEntity<ApiResponse<Status>> cancel(@PathVariable UUID id, @Valid @RequestBody Secret request, HttpServletRequest http) {
        budget(http); return ok(service.cancel(id,request));
    }
    @PostMapping("/merchant-auth/exchange") @SecurityRequirements
    @Operation(summary="Exchange approval once; same-key recovery is bounded to 60 seconds")
    public ResponseEntity<ApiResponse<TokenResponseDto>> exchange(@Valid @RequestBody Exchange request, HttpServletRequest http) {
        budget(http); limits.check("exchange",request.attemptId().toString(),20);
        return ok(service.exchange(request,http.getRemoteAddr()));
    }
    @PostMapping("/merchant-auth/refresh") @SecurityRequirements
    @Operation(summary="Rotate Merchant tokens; refresh reuse revokes this Merchant session")
    public ResponseEntity<ApiResponse<TokenResponseDto>> refresh(@Valid @RequestBody Refresh request, HttpServletRequest http) {
        budget(http); return ok(service.refresh(request));
    }
    @GetMapping("/merchant-auth/session")
    @Operation(summary="Read Merchant owner and minimal shop onboarding status")
    public ResponseEntity<ApiResponse<Identity>> identity(@AuthenticationPrincipal User user, Authentication auth) {
        return ok(service.identity(user,(UUID)auth.getDetails()));
    }
    @PostMapping("/merchant-auth/logout")
    @Operation(summary="Revoke only the current Merchant session")
    public ResponseEntity<ApiResponse<Void>> logout(@AuthenticationPrincipal User user, Authentication auth) {
        service.logout(user,(UUID)auth.getDetails()); return ok(null);
    }
    @GetMapping("/auth/merchant-sessions")
    @Operation(summary="Customer lists their active Merchant sessions")
    public ResponseEntity<ApiResponse<List<SessionInfo>>> list(@AuthenticationPrincipal User user, Authentication auth) {
        return ok(service.list(user,(UUID)auth.getDetails()));
    }
    @PostMapping("/auth/merchant-sessions/{id}/revoke")
    @Operation(summary="Customer revokes one of their own Merchant sessions")
    public ResponseEntity<ApiResponse<Void>> revoke(@AuthenticationPrincipal User user, Authentication auth, @PathVariable UUID id) {
        service.revoke(user,(UUID)auth.getDetails(),id); return ok(null);
    }
}
