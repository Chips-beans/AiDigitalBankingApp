package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.*;
import com.bank.digital_banking.common.util.HashUtils;
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
public class TelegramContinuationService {
    private final TelegramProperties properties;
    private final TelegramLoginFlowRepository flows;
    private final TelegramOidcClient telegram;
    private final ContinuationPersistence persistence;
    private final LoginAttemptService attempts;
    private final SecureRandom random = new SecureRandom();

    @Transactional
    public TelegramStartResponse start(DeviceRequest device, String ip, User linkingUser, UUID sessionId) {
        if (!properties.configured()) throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,
                "TELEGRAM_UNAVAILABLE", "Telegram login is not configured; continue with email");
        attempts.recordAttempt("telegram:start:" + HashUtils.sha256(ip));
        if (linkingUser != null) {
            persistence.requireCustomer(linkingUser);
            persistence.requireFreshLinkSession(linkingUser.getId(), sessionId);
        }
        flows.deleteExpired(OffsetDateTime.now());
        TelegramLoginFlow flow = new TelegramLoginFlow();
        flow.setId(secret());
        String exchangeSecret = secret();
        flow.setExchangeSecretHash(HashUtils.sha256(exchangeSecret));
        flow.setVerifier(secret());
        flow.setNonce(secret());
        flow.setExpiresAt(OffsetDateTime.now().plusMinutes(5));
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
                + "&redirect_uri=" + TelegramOidcClient.encode(properties.getRedirectUri())
                + "&response_type=code&scope=openid%20profile&state=" + flow.getId()
                + "&nonce=" + flow.getNonce() + "&code_challenge=" + challenge + "&code_challenge_method=S256";
        var callback = java.net.URI.create(properties.getRedirectUri());
        return new TelegramStartResponse(url, flow.getId(), exchangeSecret, 300, callback.getScheme() + "://" + callback.getAuthority());
    }
    @Transactional
    public TelegramCallbackResult callback(String state, String code, String error) {
        if (state == null || !state.matches("[A-Za-z0-9_-]{43}")) throw invalid();
        TelegramLoginFlow flow = flows.findLockedById(state).orElseThrow(this::invalid);
        if (flow.isNativeFlow() || flow.isCallbackHandled() || !flow.getExpiresAt().isAfter(OffsetDateTime.now())) throw invalid();
        flow.setCallbackHandled(true);
        String receipt = secret();
        flow.setApprovalReceiptHash(HashUtils.sha256(receipt));
        if (error != null || code == null || code.isBlank() || code.length() > 4096) {
            flow.setErrorCode("TELEGRAM_CANCELLED");
            return new TelegramCallbackResult(flow.getId(), receipt);
        }
        try {
            var identity = telegram.authenticateCode(code, flow.getVerifier(), flow.getNonce());
            flow.setSubject(identity.subject());
            flow.setFirstName(identity.firstName());
            flow.setLastName(identity.lastName());
        } catch (ApiException ex) { flow.setErrorCode(ex.getStatus().is5xxServerError() ? "TELEGRAM_UNAVAILABLE" : "TELEGRAM_REJECTED"); }
        // Authorization codes and provider tokens are never stored or returned to the browser.
        return new TelegramCallbackResult(flow.getId(), receipt);
    }
    @Transactional
    public TelegramExchangeResponse exchange(TelegramExchangeRequest request) {
        TelegramLoginFlow flow = flows.findLockedById(request.flowId()).orElseThrow(this::invalid);
        if (flow.isNativeFlow() || !MessageDigest.isEqual(flow.getExchangeSecretHash().getBytes(StandardCharsets.US_ASCII),
                HashUtils.sha256(request.exchangeSecret()).getBytes(StandardCharsets.US_ASCII))
                || flow.isClaimed() || !flow.getExpiresAt().isAfter(OffsetDateTime.now())) throw invalid();
        if (!flow.isCallbackHandled()) return new TelegramExchangeResponse("PENDING", null);
        // A separate receipt returns only to the callback window's browser opener.
        // A forwarded approval URL cannot complete the initiating browser's login.
        if (request.approvalReceipt() == null) return new TelegramExchangeResponse("PENDING", null);
        if (flow.getApprovalReceiptHash() == null || !MessageDigest.isEqual(flow.getApprovalReceiptHash().getBytes(StandardCharsets.US_ASCII),
                HashUtils.sha256(request.approvalReceipt()).getBytes(StandardCharsets.US_ASCII))) throw invalid();
        if (flow.getErrorCode() != null) return new TelegramExchangeResponse(flow.getErrorCode(), null);
        if (flow.getSubject() == null) throw invalid();
        flow.setClaimed(true);
        return new TelegramExchangeResponse("COMPLETE", persistence.telegram(flow.getSubject(), flow.getFirstName(), flow.getLastName(),
                new DeviceRequest(flow.getDeviceFingerprint(), flow.getDeviceName(), flow.getDeviceType()), flow.getIpAddress(),
                flow.getLinkedUserId(), flow.getLinkedSessionId()));
    }
    private AuthenticationFailedException invalid() { return new AuthenticationFailedException("TELEGRAM_FLOW_INVALID", "Telegram approval expired or was already used; try again"); }
    private String secret() { byte[] bytes = new byte[32]; random.nextBytes(bytes); return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes); }
}
