package com.bank.digital_banking;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import com.bank.digital_banking.module.auth.service.*;
import io.jsonwebtoken.Jwts;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.ObjectMapper;
import java.security.*;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class TelegramTokenTests {
    @Test void validatesSignatureAudienceIssuerExpiryAndNonce() throws Exception {
        var generator = KeyPairGenerator.getInstance("RSA"); generator.initialize(2048);
        var pair = generator.generateKeyPair(); var publicKey = (RSAPublicKey) pair.getPublic();
        var json = new ObjectMapper(); var props = new TelegramProperties(); props.setClientId("12345");
        var verifier = new TelegramOidcClient(props, json);
        var jwks = json.valueToTree(Map.of("keys", List.of(Map.of("kid", "test", "kty", "RSA",
                "n", unsigned(publicKey.getModulus().toByteArray()), "e", unsigned(publicKey.getPublicExponent().toByteArray())))));
        String valid = token(pair, "12345", "https://oauth.telegram.org", "nonce", Instant.now().plusSeconds(60));
        assertThat(verifier.verifyToken(valid, "nonce", jwks).subject()).isEqualTo("telegram-subject");
        for (String rejected : List.of(token(pair, "other", "https://oauth.telegram.org", "nonce", Instant.now().plusSeconds(60)),
                token(pair, "12345", "https://evil.example", "nonce", Instant.now().plusSeconds(60)),
                token(pair, "12345", "https://oauth.telegram.org", "wrong", Instant.now().plusSeconds(60)),
                token(pair, "12345", "https://oauth.telegram.org", "nonce", Instant.now().minusSeconds(60)),
                token(generator.generateKeyPair(), "12345", "https://oauth.telegram.org", "nonce", Instant.now().plusSeconds(60)))) {
            assertThatThrownBy(() -> verifier.verifyToken(rejected, "nonce", jwks)).isInstanceOf(AuthenticationFailedException.class);
        }
    }
    String unsigned(byte[] bytes) { return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes[0] == 0 ? Arrays.copyOfRange(bytes, 1, bytes.length) : bytes); }
    String token(KeyPair pair, String audience, String issuer, String nonce, Instant expiration) {
        return Jwts.builder().header().keyId("test").and().issuer(issuer).subject("telegram-subject")
                .audience().add(audience).and().issuedAt(Date.from(Instant.now().minusSeconds(120)))
                .expiration(Date.from(expiration)).claim("nonce", nonce).signWith(pair.getPrivate(), Jwts.SIG.RS256).compact();
    }
}
