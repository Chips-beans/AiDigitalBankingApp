package com.bank.digital_banking.module.auth.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class LoginRequestDto {
    
    @NotBlank(message = "Username or email is required")
    private String usernameOrEmail;

    @NotBlank(message = "Password is required")
    private String password;

    private String otpCode;

    // Device tracking fields
    @NotBlank(message = "Device fingerprint is required")
    private String deviceFingerprint;

    @NotBlank(message = "Device name is required")
    private String deviceName;

    private String deviceType; // e.g., "ANDROID", "IOS", "WEB"
}