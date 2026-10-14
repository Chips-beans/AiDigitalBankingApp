package com.bank.digital_banking.module.auth.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.auth.dto.*;
import com.bank.digital_banking.module.auth.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;

    @PostMapping("/register")
    public ResponseEntity<ApiResponse<TokenResponseDto>> register(
            @Valid @RequestBody RegisterRequestDto request,
            HttpServletRequest servletRequest) {
        
        String clientIp = extractClientIp(servletRequest);
        TokenResponseDto tokenResponse = authService.register(request, clientIp);
        
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(tokenResponse, "User registered successfully"));
    }

    @PostMapping("/login")
    public ResponseEntity<ApiResponse<TokenResponseDto>> login(
            @Valid @RequestBody LoginRequestDto request,
            HttpServletRequest servletRequest) {
        
        String clientIp = extractClientIp(servletRequest);
        TokenResponseDto tokenResponse = authService.login(request, clientIp);
        
        return ResponseEntity.ok(ApiResponse.success(tokenResponse, "Login successful"));
    }

    @PostMapping("/refresh")
    public ResponseEntity<ApiResponse<TokenResponseDto>> refreshToken(
            @Valid @RequestBody RefreshTokenRequestDto request) {
        
        TokenResponseDto tokenResponse = authService.refreshToken(request);
        return ResponseEntity.ok(ApiResponse.success(tokenResponse, "Token refreshed successfully"));
    }
    @PostMapping("/request-otp")
    public ResponseEntity<ApiResponse<String>> requestOtp(@Valid @RequestBody OtpRequestDto request) {
        authService.requestOtp(request.getEmail(), request.getPurpose());
        return ResponseEntity.ok(ApiResponse.success("OTP code sent to " + request.getEmail(), "OTP Sent"));
    }

    private String extractClientIp(HttpServletRequest request) {
        String xfHeader = request.getHeader("X-Forwarded-For");
        if (xfHeader == null || xfHeader.isEmpty()) {
            return request.getRemoteAddr();
        }
        return xfHeader.split(",")[0];
    }
}
