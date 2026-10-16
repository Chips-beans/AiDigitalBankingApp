package com.bank.digital_banking.module.auth.security;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import io.jsonwebtoken.*;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import javax.crypto.SecretKey;
import java.time.Instant;
import java.util.Date;
import java.util.Set;
import java.util.UUID;

@Component
public class JwtTokenProvider {
    private final SecretKey key;
    private final long accessMs;
    private final long refreshMs;
    private final String issuer;

    public JwtTokenProvider(@Value("${app.jwt.secret}") String secret,
            @Value("${app.jwt.expiration-ms:900000}") long accessMs,
            @Value("${app.jwt.refresh-expiration-ms:604800000}") long refreshMs,
            @Value("${app.jwt.issuer:digital-banking}") String issuer) {
        this.key = Keys.hmacShaKeyFor(Decoders.BASE64.decode(secret));
        if (accessMs <= 0 || refreshMs <= accessMs) throw new IllegalArgumentException("Invalid JWT lifetimes");
        this.accessMs = accessMs;
        this.refreshMs = refreshMs;
        this.issuer = issuer;
    }

    public String generateAccessToken(Long userId, UUID sessionId, Set<String> roles) {
        return token(userId, sessionId, "access", accessMs).claim("roles", roles).compact();
    }
    public String generateRefreshToken(Long userId, UUID sessionId) {
        return token(userId, sessionId, "refresh", refreshMs).compact();
    }
    private JwtBuilder token(Long userId, UUID sessionId, String type, long lifetime) {
        Instant now = Instant.now();
        return Jwts.builder().issuer(issuer).subject(userId.toString()).id(UUID.randomUUID().toString())
                .claim("sid", sessionId.toString()).claim("type", type)
                .issuedAt(Date.from(now)).expiration(Date.from(now.plusMillis(lifetime)))
                .signWith(key, Jwts.SIG.HS256);
    }
    public Claims parse(String token, String requiredType) {
        try {
            Claims claims = Jwts.parser().verifyWith(key).requireIssuer(issuer)
                    .require("type", requiredType).build().parseSignedClaims(token).getPayload();
            UUID.fromString(claims.get("sid", String.class));
            if (Long.parseLong(claims.getSubject()) <= 0 || claims.getId() == null
                    || claims.getExpiration() == null) throw new IllegalArgumentException();
            return claims;
        } catch (JwtException | IllegalArgumentException ex) {
            throw new AuthenticationFailedException("TOKEN_INVALID", "Token is invalid, expired, or has the wrong type");
        }
    }
    public long getAccessMs() { return accessMs; }
    public long getRefreshMs() { return refreshMs; }
}
