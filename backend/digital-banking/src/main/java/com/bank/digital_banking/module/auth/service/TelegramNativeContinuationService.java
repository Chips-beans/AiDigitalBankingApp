package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.module.auth.dto.*;
import com.bank.digital_banking.module.auth.dto.ContinuationDtos.*;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.TelegramLoginFlowRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.OffsetDateTime;
import java.util.*;

@Service @RequiredArgsConstructor
public class TelegramNativeContinuationService {
    private final TelegramProperties properties;
    private final TelegramLoginFlowRepository flows;
    private final TelegramNativeFlowClaim claims;
    private final TelegramOidcClient telegram;
    private final ContinuationPersistence persistence;
    private final LoginAttemptService attempts;
    private final SecureRandom random = new SecureRandom();

    @Transactional
    public TelegramNativeStartResponse start(DeviceRequest device, String ip, User linkingUser, UUID sessionId) {
        if (!properties.nativeConfigured()) throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,
                "TELEGRAM_UNAVAILABLE", "Native Telegram login is not configured; continue with email");
        attempts.recordAttempt("telegram:start:" + HashUtils.sha256(ip));
        if (linkingUser != null) {
            persistence.requireCustomer(linkingUser);
            persistence.requireFreshLinkSession(linkingUser.getId(), sessionId);
        }
        flows.deleteExpired(OffsetDateTime.now());
        var flow = new TelegramLoginFlow();
        flow.setId(secret());
        String exchangeSecret = secret();
        flow.setExchangeSecretHash(HashUtils.sha256(exchangeSecret));
        flow.setVerifier(secret());
        flow.setNonce(secret());
        flow.setExpiresAt(OffsetDateTime.now().plusMinutes(5));
        flow.setNativeFlow(true);
        flow.setRedirectUri(properties.getNativeRedirectUri());
        flow.setDeviceFingerprint(device.deviceFingerprint());
        flow.setDeviceName(device.deviceName());
        flow.setDeviceType(device.deviceType());
        flow.setIpAddress(ip);
        if (linkingUser != null) { flow.setLinkedUserId(linkingUser.getId()); flow.setLinkedSessionId(sessionId); }
        flows.save(flow);
        String challenge;
        try { challenge = Base64.getUrlEncoder().withoutPadding().encodeToString(
                MessageDigest.getInstance("SHA-256").digest(flow.getVerifier().getBytes(StandardCharsets.US_ASCII))); }
        catch (NoSuchAlgorithmException ex) { throw new IllegalStateException(ex); }
        String url = "https://oauth.telegram.org/auth?client_id=" + TelegramOidcClient.encode(properties.getClientId())
                + "&redirect_uri=" + TelegramOidcClient.encode(flow.getRedirectUri())
                + "&response_type=code&scope=openid%20profile&state=" + flow.getId()
                + "&nonce=" + flow.getNonce() + "&code_challenge=" + challenge + "&code_challenge_method=S256";
        return new TelegramNativeStartResponse(url, flow.getId(), exchangeSecret, 300, flow.getRedirectUri());
    }

    public TokenResponseDto exchange(TelegramNativeExchangeRequest request) {
        var flow = claims.claim(request);
        var identity = telegram.authenticateNativeCode(request.code(), flow.getVerifier(), flow.getNonce(), flow.getRedirectUri());
        return persistence.telegram(identity.subject(), identity.firstName(), identity.lastName(),
                new DeviceRequest(flow.getDeviceFingerprint(), flow.getDeviceName(), flow.getDeviceType()),
                flow.getIpAddress(), flow.getLinkedUserId(), flow.getLinkedSessionId());
    }
    private String secret() { byte[] bytes = new byte[32]; random.nextBytes(bytes); return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes); }
}
