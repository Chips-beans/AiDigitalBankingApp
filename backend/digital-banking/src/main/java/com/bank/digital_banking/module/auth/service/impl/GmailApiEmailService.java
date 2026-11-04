package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.service.EmailService;
import jakarta.mail.Message;
import jakarta.mail.Session;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Properties;
import java.util.Set;

/**
 * Sends OTP email through the Gmail API over HTTPS (app.mail.provider=gmail-api). Hosts such as Railway and Render
 * block outbound SMTP ports on their free/trial plans; HTTPS on 443 is allowed.
 *
 * <p>Uses a long-lived OAuth refresh token (scope gmail.send) for one sending Gmail account to obtain short-lived
 * access tokens, cached until shortly before expiry. Credentials go only to HTTPS endpoints (or loopback for tests).
 * Logs carry only HTTP status codes and the OAuth error code, never the OTP, recipient, tokens or response bodies.
 */
public class GmailApiEmailService implements EmailService {
    static final String DEFAULT_TOKEN_URL = "https://oauth2.googleapis.com/token";
    static final String DEFAULT_API_URL = "https://gmail.googleapis.com";
    private static final Logger log = LoggerFactory.getLogger(GmailApiEmailService.class);
    private static final Duration EARLY_REFRESH = Duration.ofSeconds(60);

    private final Settings settings;
    private final ObjectMapper json;
    private final Clock clock;
    private final HttpClient client;
    private String accessToken;
    private Instant accessTokenExpiresAt = Instant.EPOCH;

    public record Settings(String clientId, String clientSecret, String refreshToken, String sender,
                           String tokenUrl, String apiUrl, Duration timeout, int expiryMinutes) {
        public boolean configured() { return !blank(clientId) && !blank(clientSecret) && !blank(refreshToken); }
    }

    public GmailApiEmailService(Settings settings, ObjectMapper json) { this(settings, json, Clock.systemUTC()); }

    GmailApiEmailService(Settings settings, ObjectMapper json, Clock clock) {
        this.settings = settings;
        this.json = json;
        this.clock = clock;
        this.client = HttpClient.newBuilder().connectTimeout(settings.timeout())
                .followRedirects(HttpClient.Redirect.NEVER).build();
    }

    @Override
    public void sendOtpEmail(String toEmail, String otpCode, String purpose) {
        if (!settings.configured() || !secureUrl(settings.tokenUrl()) || !secureUrl(settings.apiUrl())) {
            log.warn("Gmail API email is not configured (GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GMAIL_REFRESH_TOKEN over HTTPS)");
            throw unavailable();
        }
        String raw = rawMessage(toEmail, otpCode, purpose);
        int status = send(token(false), raw);
        if (status == 401) status = send(token(true), raw); // token revoked or expired early: refresh once
        if (status / 100 != 2) {
            log.warn("Gmail API send failed with HTTP {}", status);
            throw unavailable();
        }
    }

    private int send(String token, String raw) {
        try {
            String body = json.writeValueAsString(java.util.Map.of("raw", raw));
            HttpRequest request = HttpRequest.newBuilder(URI.create(trim(settings.apiUrl()) + "/gmail/v1/users/me/messages/send"))
                    .timeout(settings.timeout())
                    .header("Authorization", "Bearer " + token)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8)).build();
            return client.send(request, HttpResponse.BodyHandlers.discarding()).statusCode();
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw unavailable();
        } catch (Exception ex) {
            log.warn("Gmail API send failed: {}", ex.getClass().getSimpleName());
            throw unavailable();
        }
    }

    private synchronized String token(boolean forceRefresh) {
        Instant now = clock.instant();
        if (!forceRefresh && accessToken != null && now.isBefore(accessTokenExpiresAt.minus(EARLY_REFRESH))) return accessToken;
        accessToken = null;
        String form = "grant_type=refresh_token"
                + "&client_id=" + enc(settings.clientId())
                + "&client_secret=" + enc(settings.clientSecret())
                + "&refresh_token=" + enc(settings.refreshToken());
        HttpResponse<String> response;
        try {
            HttpRequest request = HttpRequest.newBuilder(URI.create(settings.tokenUrl().trim()))
                    .timeout(settings.timeout())
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .POST(HttpRequest.BodyPublishers.ofString(form, StandardCharsets.UTF_8)).build();
            response = client.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw unavailable();
        } catch (Exception ex) {
            log.warn("Gmail OAuth token refresh failed: {}", ex.getClass().getSimpleName());
            throw unavailable();
        }
        JsonNode node = parse(response.body());
        if (response.statusCode() / 100 != 2 || node == null || !node.path("access_token").isString()
                || node.path("access_token").asString().isBlank()) {
            // invalid_grant usually means the refresh token expired (7 days in Testing mode) or was revoked.
            log.warn("Gmail OAuth token refresh failed with HTTP {} ({})", response.statusCode(), oauthError(node));
            throw unavailable();
        }
        accessToken = node.path("access_token").asString();
        long expiresIn = node.path("expires_in").isNumber() ? node.path("expires_in").asLong() : 300;
        accessTokenExpiresAt = now.plusSeconds(Math.max(0, expiresIn));
        return accessToken;
    }

    String rawMessage(String toEmail, String otpCode, String purpose) {
        try {
            // Without these, Message-ID generation does a local hostname lookup (≈5 s on some hosts); Gmail sets its own anyway.
            Properties props = new Properties();
            props.setProperty("mail.host", "localhost");
            props.setProperty("mail.from", blank(settings.sender()) ? "otp@localhost" : settings.sender().trim());
            MimeMessage message = new MimeMessage(Session.getInstance(props));
            if (!blank(settings.sender())) message.setFrom(new InternetAddress(settings.sender().trim()));
            message.setRecipients(Message.RecipientType.TO, InternetAddress.parse(toEmail, true));
            message.setSubject(OtpEmailText.subject(purpose), "UTF-8");
            message.setText(OtpEmailText.body(otpCode, settings.expiryMinutes()), "UTF-8");
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            message.writeTo(out);
            return Base64.getUrlEncoder().withoutPadding().encodeToString(out.toByteArray());
        } catch (Exception ex) {
            log.warn("Could not build OTP email: {}", ex.getClass().getSimpleName());
            throw unavailable();
        }
    }

    private JsonNode parse(String body) {
        try { return body == null || body.isBlank() ? null : json.readTree(body); }
        catch (Exception ex) { return null; }
    }

    /** Only a short OAuth error code such as invalid_grant; never the description or any other body text. */
    static String oauthError(JsonNode node) {
        if (node == null || !node.path("error").isString()) return "no error code";
        String code = node.path("error").asString();
        return code.matches("[a-z_]{1,40}") ? code : "unrecognised error code";
    }

    static boolean secureUrl(String url) {
        try {
            if (blank(url)) return false;
            URI uri = URI.create(url.trim());
            if ("https".equalsIgnoreCase(uri.getScheme()) && uri.getHost() != null) return true;
            return "http".equalsIgnoreCase(uri.getScheme()) && Set.of("localhost", "127.0.0.1", "[::1]").contains(uri.getHost());
        } catch (IllegalArgumentException ex) { return false; }
    }

    private static ApiException unavailable() {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "OTP_DELIVERY_UNAVAILABLE", "Verification email could not be delivered; try again later");
    }
    private static String enc(String value) { return URLEncoder.encode(value.trim(), StandardCharsets.UTF_8); }
    private static String trim(String url) { return url.trim().replaceAll("/+$", ""); }
    private static boolean blank(String value) { return value == null || value.isBlank(); }
}
