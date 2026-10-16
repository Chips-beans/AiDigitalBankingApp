package com.bank.digital_banking;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import com.bank.digital_banking.module.auth.security.JwtTokenProvider;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtTokenProviderTests {
    private static final String SECRET = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=";
    private final JwtTokenProvider tokens = new JwtTokenProvider(SECRET, 900000, 604800000, "digital-banking");

    @Test void signedTokenWithoutSessionClaimReturnsAuthenticationFailure() {
        String token = Jwts.builder().issuer("digital-banking").subject("1")
                .claim("type", "access").id(UUID.randomUUID().toString())
                .issuedAt(new Date()).expiration(Date.from(Instant.now().plusSeconds(60)))
                .signWith(Keys.hmacShaKeyFor(Decoders.BASE64.decode(SECRET)), Jwts.SIG.HS256).compact();
        assertThatThrownBy(() -> tokens.parse(token, "access"))
                .isInstanceOf(AuthenticationFailedException.class);
    }
}
