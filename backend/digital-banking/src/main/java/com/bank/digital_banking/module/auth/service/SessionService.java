package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.module.audit.service.AuditTrail;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.module.auth.dto.TokenResponseDto;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.AuthSessionRepository;
import com.bank.digital_banking.module.auth.security.JwtTokenProvider;
import io.jsonwebtoken.Claims;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.OffsetDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Service @RequiredArgsConstructor
public class SessionService {
    private final AuthSessionRepository sessions;
    private final JwtTokenProvider tokens;
    private final AuditTrail audit;
    private final org.springframework.jdbc.core.JdbcTemplate jdbc;

    public boolean isPinLocked(UUID id) {
        return Boolean.TRUE.equals(jdbc.queryForObject("SELECT EXISTS(SELECT 1 FROM app_pin_locks WHERE session_id=? AND locked=TRUE)", Boolean.class, id));
    }
    private int pinGeneration(UUID id) {
        return jdbc.queryForObject("SELECT COALESCE((SELECT pin_generation FROM app_pin_locks WHERE session_id=?),0)", Integer.class, id);
    }

    @Transactional
    public TokenResponseDto issueAfterPin(AuthSession session) { requirePurpose(session, "CUSTOMER"); return issue(session); }

    @Transactional
    public TokenResponseDto create(User user, Device device) {
        OffsetDateTime now = OffsetDateTime.now();
        sessions.revokeForDevice(user.getId(), device.getId(), now);
        AuthSession session = AuthSession.builder().id(UUID.randomUUID()).user(user).device(device)
                .createdAt(now).expiresAt(now.plusSeconds(tokens.getRefreshMs() / 1000)).build();
        return issue(session);
    }

    // Failed reuse must commit revocation, rather than roll it back with the exception.
    @Transactional(noRollbackFor = AuthenticationFailedException.class)
    public TokenResponseDto refresh(String rawToken) {
        return refreshForPurpose(rawToken, "CUSTOMER");
    }

    @Transactional(noRollbackFor = AuthenticationFailedException.class)
    public TokenResponseDto refreshMerchant(String rawToken) {
        return refreshForPurpose(rawToken, "MERCHANT");
    }

    private TokenResponseDto refreshForPurpose(String rawToken, String purpose) {
        Claims claims = tokens.parse(rawToken, "refresh");
        AuthSession session = sessions.findLockedById(UUID.fromString(claims.get("sid", String.class)))
                .orElseThrow(() -> failure("SESSION_INVALID", "Session is not available"));
        validate(session, claims);
        requirePurpose(session, purpose);
        if (isPinLocked(session.getId())) throw new com.bank.digital_banking.common.exception.ApiException(
                org.springframework.http.HttpStatus.FORBIDDEN, "PIN_REQUIRED", "Unlock the app with your PIN");
        if (!MessageDigest.isEqual(session.getRefreshTokenHash().getBytes(StandardCharsets.US_ASCII),
                HashUtils.sha256(rawToken).getBytes(StandardCharsets.US_ASCII))) {
            session.setRevokedAt(OffsetDateTime.now());
            sessions.save(session);
            throw failure("REFRESH_REUSED", "Refresh token was already used; sign in again");
        }
        var response = issue(session);
        audit.successAs(session.getUser(), "AUTH", "REFRESH", session.getId().toString());
        return response;
    }

    @Transactional
    public TokenResponseDto createMerchant(User user, Device device) {
        // Never replace the Customer session, even on the same physical device.
        sessions.revokeMerchantForDevice(user.getId(),device.getId(),OffsetDateTime.now());
        AuthSession session = AuthSession.builder().id(UUID.randomUUID()).user(user).device(device)
                .purpose("MERCHANT").clientId("kesor-merchant-android").createdAt(OffsetDateTime.now())
                .expiresAt(OffsetDateTime.now().plusSeconds(tokens.getRefreshMs() / 1000)).build();
        return issue(session);
    }

    public void requirePurpose(AuthSession session, String purpose) {
        if (!purpose.equals(session.getPurpose())) throw failure(
                purpose.equals("MERCHANT") ? "MERCHANT_SESSION_REQUIRED" : "CUSTOMER_SESSION_REQUIRED",
                "This session cannot be used for this action");
    }

    @Transactional(readOnly = true)
    public AuthSession authenticate(String rawToken) {
        Claims claims = tokens.parse(rawToken, "access");
        AuthSession session = sessions.findById(UUID.fromString(claims.get("sid", String.class)))
                .orElseThrow(() -> failure("SESSION_INVALID", "Session is not available"));
        validate(session, claims);
        int supplied = claims.get("pin_epoch") instanceof Number n ? n.intValue() : 0;
        if (supplied != pinGeneration(session.getId())) throw new com.bank.digital_banking.common.exception.ApiException(
                org.springframework.http.HttpStatus.FORBIDDEN, "PIN_REQUIRED", "This access token predates the latest app unlock");
        // Initialize current roles while the persistence context is open.
        session.getUser().getRoles().size();
        return session;
    }

    @Transactional
    public void logout(UUID sessionId) {
        sessions.findLockedById(sessionId).ifPresent(session -> {
            if (session.getRevokedAt() == null) {
                session.setRevokedAt(OffsetDateTime.now());
                sessions.save(session);
                audit.successAs(session.getUser(), "AUTH", "LOGOUT", session.getId().toString());
            }
        });
    }

    private void validate(AuthSession session, Claims claims) {
        String purpose = claims.get("purpose", String.class);
        // Pre-V18 signed Customer tokens had no audience/purpose. Only the
        // backfilled Customer rows may accept that exact legacy claim shape.
        boolean legacy = purpose == null && claims.getAudience() == null && claims.get("client_id") == null;
        if (!(legacy && "CUSTOMER".equals(session.getPurpose())) &&
                (!session.getPurpose().equals(purpose) || !session.getClientId().equals(claims.get("client_id", String.class))
                 || !Set.of("MERCHANT".equals(purpose) ? "kesor-merchant" : "kesor-customer").equals(claims.getAudience())))
            throw failure("TOKEN_INVALID", "Session audience is invalid");
        if (!session.getUser().getId().toString().equals(claims.getSubject())
                || session.getRevokedAt() != null || !session.getExpiresAt().isAfter(OffsetDateTime.now()))
            throw failure("SESSION_INVALID", "Session is expired or revoked");
        if (!session.getUser().isEnabled()) throw failure("USER_DISABLED", "Account is disabled");
        if ("MERCHANT".equals(session.getPurpose()) && (!session.getUser().isProfileComplete()
                || session.getUser().getRoles().stream().noneMatch(r -> r.getName() == ERole.ROLE_CUSTOMER)))
            throw failure("SESSION_INVALID", "Merchant owner is no longer eligible");
        if (session.getDevice().getStatus() != DeviceStatus.ACTIVE)
            throw failure("DEVICE_REVOKED", "Device is not active");
    }

    private TokenResponseDto issue(AuthSession session) {
        User user = session.getUser();
        if ("MERCHANT".equals(session.getPurpose())) {
            String refresh = tokens.generateMerchantToken(user.getId(), session.getId(), "refresh");
            session.setRefreshTokenHash(HashUtils.sha256(refresh));
            sessions.saveAndFlush(session);
            return TokenResponseDto.builder().accessToken(tokens.generateMerchantToken(user.getId(), session.getId(), "access"))
                    .refreshToken(refresh).tokenType("Bearer").expiresInMs(Math.min(tokens.getAccessMs(), 300000))
                    .refreshExpiresAt(session.getExpiresAt().withOffsetSameInstant(java.time.ZoneOffset.UTC)).sessionId(session.getId()).userId(user.getId())
                    .roles(Set.of("MERCHANT_SESSION")).build();
        }
        Set<String> roles = user.getRoles().stream().map(r -> r.getName().name()).collect(Collectors.toSet());
        String refresh = tokens.generateRefreshToken(user.getId(), session.getId());
        session.setRefreshTokenHash(HashUtils.sha256(refresh));
        sessions.save(session);
        return TokenResponseDto.builder().accessToken(tokens.generateAccessToken(user.getId(), session.getId(), roles, pinGeneration(session.getId())))
                .refreshToken(refresh).tokenType("Bearer").expiresInMs(tokens.getAccessMs())
                .refreshExpiresAt(session.getExpiresAt()).sessionId(session.getId()).userId(user.getId())
                .username(user.getUsername()).email(user.getEmail()).roles(roles).build();
    }
    private static AuthenticationFailedException failure(String code, String message) {
        return new AuthenticationFailedException(code, message);
    }
}
