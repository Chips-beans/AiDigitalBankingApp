package com.bank.digital_banking.module.auth.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.dto.*;
import com.bank.digital_banking.module.auth.dto.ContinuationDtos.*;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.service.*;
import jakarta.servlet.http.*;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController @RequestMapping("/api/v1/auth") @RequiredArgsConstructor
public class ContinuationController {
    private final OtpService otps;
    private final ContinuationPersistence persistence;
    private final TelegramContinuationService telegram;
    private final TelegramProperties properties;
    private final tools.jackson.databind.ObjectMapper json;

    @ModelAttribute
    public void noStore(HttpServletResponse response) {
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("Pragma", "no-cache");
        response.setHeader("Referrer-Policy", "no-referrer");
    }
    @PostMapping("/email/request")
    public ApiResponse<OtpResponseDto> request(@Valid @RequestBody EmailRequest request) {
        return ApiResponse.success(otps.generateAndSendOtp(email(request.email()), "CONTINUE", true), "Code requested");
    }
    @PostMapping("/email/verify")
    public ApiResponse<TokenResponseDto> verify(@Valid @RequestBody EmailVerifyRequest request, HttpServletRequest http) {
        String email = email(request.email());
        otps.validateOtp(email, request.otpCode(), "CONTINUE");
        return ApiResponse.success(persistence.email(email, request.device(), http.getRemoteAddr()), "Continue successful");
    }
    @PatchMapping("/profile")
    public ApiResponse<SessionIdentityDto> profile(@AuthenticationPrincipal User user, Authentication auth,
                                                  @Valid @RequestBody ProfileRequest request) {
        User completed = persistence.complete(user.getId(), request);
        return ApiResponse.success(SessionIdentityDto.from(completed, (UUID) auth.getDetails()), "Profile completed");
    }
    @PostMapping("/email/link/request")
    public ApiResponse<OtpResponseDto> linkRequest(@AuthenticationPrincipal User user, @Valid @RequestBody EmailRequest request) {
        persistence.requireCustomer(user);
        return ApiResponse.success(otps.generateAndSendOtp(email(request.email()), "LINK_" + user.getId(), true), "Code requested");
    }
    @PostMapping("/email/link/verify")
    public ApiResponse<TokenResponseDto> linkVerify(@AuthenticationPrincipal User user,
            @Valid @RequestBody EmailVerifyRequest request, HttpServletRequest http) {
        persistence.requireCustomer(user);
        String email = email(request.email());
        otps.validateOtp(email, request.otpCode(), "LINK_" + user.getId());
        return ApiResponse.success(persistence.linkEmail(user.getId(), email, request.device(), http.getRemoteAddr()), "Email connected");
    }
    @PostMapping("/telegram/start")
    public ApiResponse<TelegramStartResponse> start(@Valid @RequestBody DeviceRequest request, HttpServletRequest http) {
        return ApiResponse.success(telegram.start(request, http.getRemoteAddr(), null, null), "Approve in Telegram");
    }
    @PostMapping("/telegram/link/start")
    public ApiResponse<TelegramStartResponse> linkStart(@AuthenticationPrincipal User user, Authentication auth,
            @Valid @RequestBody DeviceRequest request, HttpServletRequest http) {
        return ApiResponse.success(telegram.start(request, http.getRemoteAddr(), user, (UUID) auth.getDetails()), "Approve in Telegram");
    }
    @PostMapping("/telegram/exchange")
    public ApiResponse<TelegramExchangeResponse> exchange(@Valid @RequestBody TelegramExchangeRequest request) {
        return ApiResponse.success(telegram.exchange(request), "Telegram continuation");
    }
    @GetMapping(value = "/telegram/callback", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> callback(@RequestParam(required = false) String state,
            @RequestParam(required = false) String code, @RequestParam(required = false) String error) {
        boolean accepted = true;
        TelegramCallbackResult result = null;
        try { result = telegram.callback(state, code, error); } catch (ApiException ex) { accepted = false; }
        String message = accepted ? "Return to the Kesor Bank window to continue. You may close this window."
                : "This approval is no longer available. Return to Kesor Bank and try again.";
        String script = "";
        String nonce = UUID.randomUUID().toString();
        if (result != null) {
            String payload = json.writeValueAsString(Map.of("type", "kesor.telegram.approved", "flowId", result.flowId(), "approvalReceipt", result.approvalReceipt()));
            script = "<script nonce=\"" + nonce + "\">if(window.opener){window.opener.postMessage("
                    + json.writeValueAsString(payload) + "," + json.writeValueAsString(properties.getFrontendOrigin()) + ");}</script>";
        }
        return ResponseEntity.status(accepted ? 200 : 400)
                .header("Content-Security-Policy", "default-src 'none'; script-src 'nonce-" + nonce + "'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'")
                .body("<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
                        + "<title>Kesor Bank · Telegram</title><body style=\"font:18px system-ui;background:#faf9f6;color:#142d4e;padding:48px;line-height:1.6\">"
                        + "<h1>Kesor Bank</h1><p>" + message + "</p>" + script + "</body></html>");
    }
    private String email(String email) { return email.strip().toLowerCase(Locale.ROOT); }
}
