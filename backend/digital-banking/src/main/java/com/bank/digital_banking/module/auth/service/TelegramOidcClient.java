package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import io.jsonwebtoken.Jwts;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.math.BigInteger;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.time.*;
import java.util.*;

@Component @RequiredArgsConstructor
public class TelegramOidcClient {
    public record Identity(String subject, String firstName, String lastName) {}
    private final TelegramProperties properties;
    private final ObjectMapper json;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5))
            .followRedirects(HttpClient.Redirect.NEVER).build();
    private volatile JsonNode cachedKeys;
    private volatile Instant keysUntil = Instant.EPOCH;

    /** Registered native applications are public OAuth clients; their secret never enters the APK. */
    public Identity authenticateNativeCode(String code, String verifier, String nonce, String redirectUri) {
        try {
            String body = "grant_type=authorization_code&code=" + encode(code)
                    + "&redirect_uri=" + encode(redirectUri) + "&client_id=" + encode(properties.getClientId())
                    + "&code_verifier=" + encode(verifier);
            HttpResponse<String> response = http.send(HttpRequest.newBuilder(URI.create("https://oauth.telegram.org/token"))
                    .timeout(Duration.ofSeconds(5)).header("Content-Type", "application/x-www-form-urlencoded")
                    .POST(HttpRequest.BodyPublishers.ofString(body)).build(), HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() != 200) throw new AuthenticationFailedException("TELEGRAM_REJECTED", "Telegram approval could not be verified");
            return verifyToken(json.readTree(response.body()).path("id_token").asText(), nonce, keys());
        } catch (ApiException ex) { throw ex; }
        catch (InterruptedException ex) { Thread.currentThread().interrupt(); throw unavailable(); }
        catch (Exception ex) { throw unavailable(); }
    }

    public Identity authenticateCode(String code, String verifier, String nonce) {
        try {
            String body = "grant_type=authorization_code&code=" + encode(code)
                    + "&redirect_uri=" + encode(properties.getRedirectUri())
                    + "&client_id=" + encode(properties.getClientId()) + "&code_verifier=" + encode(verifier);
            String basic = Base64.getEncoder().encodeToString((properties.getClientId() + ":" + properties.getClientSecret())
                    .getBytes(StandardCharsets.UTF_8));
            HttpResponse<String> response = http.send(HttpRequest.newBuilder(URI.create("https://oauth.telegram.org/token"))
                    .timeout(Duration.ofSeconds(5)).header("Content-Type", "application/x-www-form-urlencoded")
                    .header("Authorization", "Basic " + basic).POST(HttpRequest.BodyPublishers.ofString(body)).build(),
                    HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() != 200) throw new AuthenticationFailedException("TELEGRAM_REJECTED", "Telegram approval could not be verified");
            String token = json.readTree(response.body()).path("id_token").asText();
            return verifyToken(token, nonce, keys());
        } catch (ApiException ex) { throw ex; }
        catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw unavailable();
        } catch (Exception ex) { throw unavailable(); }
    }
    private synchronized JsonNode keys() throws Exception {
        if (cachedKeys != null && keysUntil.isAfter(Instant.now())) return cachedKeys;
        HttpResponse<String> response = http.send(HttpRequest.newBuilder(URI.create("https://oauth.telegram.org/.well-known/jwks.json"))
                .timeout(Duration.ofSeconds(5)).GET().build(), HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) throw unavailable();
        cachedKeys = json.readTree(response.body());
        keysUntil = Instant.now().plusSeconds(300);
        return cachedKeys;
    }
    /** Signature, issuer, audience, nonce, expiration and subject must all be valid. */
    public Identity verifyToken(String token, String nonce, JsonNode jwks) {
        try {
            if (token == null || token.length() > 16000) throw new IllegalArgumentException();
            String[] parts = token.split("\\.");
            if (parts.length != 3) throw new IllegalArgumentException();
            JsonNode header = json.readTree(Base64.getUrlDecoder().decode(parts[0]));
            if (!"RS256".equals(header.path("alg").asText()) || header.path("kid").asText().isBlank())
                throw new IllegalArgumentException();
            for (JsonNode key : jwks.path("keys")) {
                if (!header.path("kid").asText().equals(key.path("kid").asText()) || !"RSA".equals(key.path("kty").asText())) continue;
                RSAPublicKey publicKey = (RSAPublicKey) KeyFactory.getInstance("RSA").generatePublic(new RSAPublicKeySpec(
                        new BigInteger(1, Base64.getUrlDecoder().decode(key.path("n").asText())),
                        new BigInteger(1, Base64.getUrlDecoder().decode(key.path("e").asText()))));
                var claims = Jwts.parser().verifyWith(publicKey).requireIssuer("https://oauth.telegram.org")
                        .requireAudience(properties.getClientId()).require("nonce", nonce).clockSkewSeconds(30)
                        .build().parseSignedClaims(token).getPayload();
                if (claims.getExpiration() == null || claims.getIssuedAt() == null
                        || claims.getIssuedAt().toInstant().isAfter(Instant.now().plusSeconds(30))
                        || claims.getSubject() == null || claims.getSubject().isBlank() || claims.getSubject().length() > 128)
                    throw new IllegalArgumentException();
                return new Identity(claims.getSubject(), name(claims.get("given_name", String.class)),
                        name(claims.get("family_name", String.class)));
            }
            // Refresh a rotated key set on the next attempt, without trusting a JWT-supplied URL.
            keysUntil = Instant.EPOCH;
            throw new IllegalArgumentException();
        } catch (Exception ex) {
            throw new AuthenticationFailedException("TELEGRAM_REJECTED", "Telegram approval could not be verified");
        }
    }
    private String name(String value) { return value == null ? null : value.strip().substring(0, Math.min(value.strip().length(), 50)); }
    public static String encode(String value) { return URLEncoder.encode(value, StandardCharsets.UTF_8); }
    private ApiException unavailable() {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "TELEGRAM_UNAVAILABLE", "Telegram is unavailable; try again or continue with email");
    }
}
