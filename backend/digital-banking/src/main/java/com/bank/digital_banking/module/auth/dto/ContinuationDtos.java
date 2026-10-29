package com.bank.digital_banking.module.auth.dto;

import jakarta.validation.constraints.*;

public final class ContinuationDtos {
    private ContinuationDtos() {}

    public record EmailRequest(@NotBlank @Email @Size(max = 100) String email) {}
    public record EmailVerifyRequest(
            @NotBlank @Email @Size(max = 100) String email,
            @NotBlank @Pattern(regexp = "[0-9]{6}") String otpCode,
            @NotBlank @Size(max = 255) String deviceFingerprint,
            @NotBlank @Size(max = 100) String deviceName,
            @Size(max = 50) String deviceType) {
        public DeviceRequest device() { return new DeviceRequest(deviceFingerprint, deviceName, deviceType); }
    }
    public record DeviceRequest(
            @NotBlank @Size(max = 255) String deviceFingerprint,
            @NotBlank @Size(max = 100) String deviceName,
            @Size(max = 50) String deviceType) {}
    public record ProfileRequest(
            @NotBlank @Size(max = 50) String firstName,
            @NotBlank @Size(max = 50) String lastName) {}
    public record TelegramStartResponse(String authorizationUrl, String flowId, String exchangeSecret, int expiresInSeconds, String callbackOrigin) {}
    public record TelegramNativeStartResponse(String authorizationUrl, String flowId, String exchangeSecret,
                                              int expiresInSeconds, String redirectUri) {}
    public record TelegramNativeExchangeRequest(
            @NotBlank @Pattern(regexp = "[A-Za-z0-9_-]{43}") String flowId,
            @NotBlank @Pattern(regexp = "[A-Za-z0-9_-]{43}") String exchangeSecret,
            @NotBlank @Size(max = 4096) String code) {}
    public record TelegramCallbackResult(String flowId, String approvalReceipt) {}
    public record TelegramExchangeRequest(
            @NotBlank @Pattern(regexp = "[A-Za-z0-9_-]{43}") String flowId,
            @NotBlank @Pattern(regexp = "[A-Za-z0-9_-]{43}") String exchangeSecret,
            @Pattern(regexp = "[A-Za-z0-9_-]{43}") String approvalReceipt) {}
    public record TelegramExchangeResponse(String status, TokenResponseDto tokens) {}
}
