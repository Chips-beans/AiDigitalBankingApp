package com.bank.digital_banking.module.auth.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.dto.*;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.service.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.UUID;

@RestController @RequestMapping("/api/v1/auth") @RequiredArgsConstructor
public class AuthController {
    private final AuthService auth;
    private final SessionService sessions;

    @PostMapping("/request-otp")
    public ResponseEntity<ApiResponse<OtpResponseDto>> requestOtp(@Valid @RequestBody OtpRequestDto request) {
        return ResponseEntity.ok(ApiResponse.success(auth.requestOtp(request.getEmail(), request.getPurpose()), "OTP request accepted"));
    }
    @PostMapping("/register")
    public ResponseEntity<ApiResponse<TokenResponseDto>> register(@Valid @RequestBody RegisterRequestDto request, HttpServletRequest http) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.success(auth.register(request, http.getRemoteAddr()), "User registered successfully"));
    }
    @PostMapping("/login")
    public ResponseEntity<ApiResponse<TokenResponseDto>> login(@Valid @RequestBody LoginRequestDto request, HttpServletRequest http) {
        return ResponseEntity.ok(ApiResponse.success(auth.login(request, http.getRemoteAddr()), "Login successful"));
    }
    @PostMapping("/refresh")
    public ResponseEntity<ApiResponse<TokenResponseDto>> refresh(@Valid @RequestBody RefreshTokenRequestDto request) {
        return ResponseEntity.ok(ApiResponse.success(auth.refreshToken(request), "Token refreshed successfully"));
    }
    @GetMapping("/me")
    public ResponseEntity<ApiResponse<SessionIdentityDto>> me(@AuthenticationPrincipal User user, Authentication authentication) {
        return ResponseEntity.ok(ApiResponse.success(SessionIdentityDto.from(user, (UUID) authentication.getDetails()), "Current session"));
    }
    @PostMapping("/logout")
    public ResponseEntity<ApiResponse<Void>> logout(Authentication authentication) {
        sessions.logout((UUID) authentication.getDetails());
        return ResponseEntity.ok(ApiResponse.success("Session revoked"));
    }
}
