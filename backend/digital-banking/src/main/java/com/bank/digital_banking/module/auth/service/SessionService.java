package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
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
import java.security.NoSuchAlgorithmException;
import java.time.OffsetDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Service @RequiredArgsConstructor
public class SessionService {
    private final AuthSessionRepository sessions;
    private final JwtTokenProvider tokens;

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
        Claims claims = tokens.parse(rawToken, "refresh");
        AuthSession session = sessions.findLockedById(UUID.fromString(claims.get("sid", String.class)))
                .orElseThrow(() -> failure("SESSION_INVALID", "Session is not available"));
        validate(session, claims);
        if (!MessageDigest.isEqual(session.getRefreshTokenHash().getBytes(StandardCharsets.US_ASCII),
                hash(rawToken).getBytes(StandardCharsets.US_ASCII))) {
            session.setRevokedAt(OffsetDateTime.now());
            sessions.save(session);
            throw failure("REFRESH_REUSED", "Refresh token was already used; sign in again");
        }
        return issue(session);
    }

    @Transactional(readOnly = true)
    public AuthSession authenticate(String rawToken) {
        Claims claims = tokens.parse(rawToken, "access");
        AuthSession session = sessions.findById(UUID.fromString(claims.get("sid", String.class)))
                .orElseThrow(() -> failure("SESSION_INVALID", "Session is not available"));
        validate(session, claims);
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
            }
        });
    }

    private void validate(AuthSession session, Claims claims) {
        if (!session.getUser().getId().toString().equals(claims.getSubject())
                || session.getRevokedAt() != null || !session.getExpiresAt().isAfter(OffsetDateTime.now()))
            throw failure("SESSION_INVALID", "Session is expired or revoked");
        if (!session.getUser().isEnabled()) throw failure("USER_DISABLED", "Account is disabled");
        if (session.getDevice().getStatus() != DeviceStatus.ACTIVE)
            throw failure("DEVICE_REVOKED", "Device is not active");
    }

    private TokenResponseDto issue(AuthSession session) {
        User user = session.getUser();
        Set<String> roles = user.getRoles().stream().map(r -> r.getName().name()).collect(Collectors.toSet());
        String refresh = tokens.generateRefreshToken(user.getId(), session.getId());
        session.setRefreshTokenHash(hash(refresh));
        sessions.save(session);
        return TokenResponseDto.builder().accessToken(tokens.generateAccessToken(user.getId(), session.getId(), roles))
                .refreshToken(refresh).tokenType("Bearer").expiresInMs(tokens.getAccessMs())
                .refreshExpiresAt(session.getExpiresAt()).sessionId(session.getId()).userId(user.getId())
                .username(user.getUsername()).email(user.getEmail()).roles(roles).build();
    }
    private static String hash(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException ex) { throw new IllegalStateException(ex); }
    }
    private static AuthenticationFailedException failure(String code, String message) {
        return new AuthenticationFailedException(code, message);
    }
}
