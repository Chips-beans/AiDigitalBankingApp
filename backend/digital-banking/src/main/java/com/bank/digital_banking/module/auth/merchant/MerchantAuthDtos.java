package com.bank.digital_banking.module.auth.merchant;

import jakarta.validation.constraints.*;
import java.time.OffsetDateTime;
import java.util.UUID;

public final class MerchantAuthDtos {
    private MerchantAuthDtos() {}
    public record Start(@NotBlank @Size(max=80) String clientId,
                        @NotBlank @Size(max=500) String redirectUri,
                        @NotNull @Pattern(regexp="[A-Za-z0-9_-]{43,128}") String state,
                        @NotNull @Pattern(regexp="[A-Za-z0-9_-]{43}") String codeChallenge,
                        @NotNull @Pattern(regexp="S256") String codeChallengeMethod,
                        @NotNull @Pattern(regexp="[0-9a-f]{64}") String attemptSecretHash,
                        @NotNull @Pattern(regexp="[A-Za-z0-9_-]{22,128}") String installationId,
                        @NotBlank @Size(max=100) @Pattern(regexp="[^\\p{Cntrl}]+") String deviceName) {}
    public record Started(UUID attemptId, OffsetDateTime expiresAt, String approvalUri, String customerPackage) {}
    public record Secret(@NotNull @Pattern(regexp="[A-Za-z0-9_-]{43,128}") String attemptSecret) {}
    public record Handoff(@NotNull @Pattern(regexp="[A-Za-z0-9_-]{43}") String handoffToken) {}
    public record Approve(@NotNull @Pattern(regexp="[A-Za-z0-9_-]{43}") String handoffToken,
                          @NotNull @Pattern(regexp="[0-9]{4}") String pin) {}
    public record Exchange(@NotNull UUID attemptId,
                           @NotNull @Pattern(regexp="[A-Za-z0-9_-]{43}") String code,
                           @NotNull @Pattern(regexp="[A-Za-z0-9._~-]{43,128}") String codeVerifier,
                           @NotNull @Pattern(regexp="[A-Za-z0-9_-]{43,128}") String attemptSecret,
                           @NotNull @Pattern(regexp="[A-Za-z0-9_-]{43,128}") String exchangeKey,
                           @NotNull @Pattern(regexp="[A-Za-z0-9_-]{43,128}") String state,
                           @NotBlank @Size(max=80) String clientId,
                           @NotBlank @Size(max=500) String redirectUri) {}
    public record Refresh(@NotBlank @Size(max=4096) String refreshToken) {}
    public record Status(UUID attemptId, String status, OffsetDateTime expiresAt) {}
    public record Details(UUID attemptId, String clientName, String deviceName, String status,
                          OffsetDateTime expiresAt, String merchantPackage) {}
    public record Callback(String callbackUri, String merchantPackage) {}
    public record Shop(String merchantId, String storeName, String status) {}
    public record Identity(UUID sessionId, long ownerId, String clientId, String onboardingState, Shop shop) {}
    public record SessionInfo(UUID sessionId, String clientName, String deviceName,
                              OffsetDateTime createdAt, OffsetDateTime expiresAt) {}
}
