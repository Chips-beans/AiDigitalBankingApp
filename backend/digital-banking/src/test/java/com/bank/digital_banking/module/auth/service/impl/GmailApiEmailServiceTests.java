package com.bank.digital_banking.module.auth.service.impl;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.bank.digital_banking.common.exception.ApiException;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.json.JsonMapper;

import java.io.ByteArrayInputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Gmail API OTP delivery against a loopback fake of Google's token and send endpoints (no real network). */
class GmailApiEmailServiceTests {
    static final String CLIENT_ID = "client-id-123.apps.googleusercontent.com";
    static final String CLIENT_SECRET = "client-secret-value-xyz";
    static final String REFRESH_TOKEN = "1//refresh-token-value-abc";
    static final String OTP = "482913";

    final JsonMapper json = JsonMapper.builder().build();
    HttpServer server;
    String base;
    final AtomicInteger tokenHits = new AtomicInteger();
    final AtomicInteger sendHits = new AtomicInteger();
    final List<String> tokenForms = new CopyOnWriteArrayList<>();
    final List<String> sendAuth = new CopyOnWriteArrayList<>();
    final List<String> sendBodies = new CopyOnWriteArrayList<>();
    volatile int tokenStatus = 200;
    volatile String tokenBody = "{\"access_token\":\"access-1\",\"expires_in\":3599,\"token_type\":\"Bearer\"}";
    final List<Integer> sendStatuses = new CopyOnWriteArrayList<>();
    volatile long sendDelayMs = 0;
    ListAppender<ILoggingEvent> logs;
    Logger logger;

    @BeforeEach
    void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        server.createContext("/token", exchange -> {
            int n = tokenHits.incrementAndGet();
            tokenForms.add(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            String body = tokenBody.replace("access-1", "access-" + n);
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(tokenStatus, bytes.length);
            exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        server.createContext("/gmail/v1/users/me/messages/send", exchange -> {
            int n = sendHits.incrementAndGet();
            sendAuth.add(exchange.getRequestHeaders().getFirst("Authorization"));
            sendBodies.add(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            if (sendDelayMs > 0) try { Thread.sleep(sendDelayMs); } catch (InterruptedException ex) { Thread.currentThread().interrupt(); }
            int status = sendStatuses.size() >= n ? sendStatuses.get(n - 1) : 200;
            byte[] bytes = "{\"id\":\"msg-1\",\"error\":{\"message\":\"secret provider text\"}}".getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(status, bytes.length);
            exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        server.start();
        base = "http://127.0.0.1:" + server.getAddress().getPort();
        logger = (Logger) LoggerFactory.getLogger(GmailApiEmailService.class);
        logs = new ListAppender<>();
        logs.start();
        logger.addAppender(logs);
    }

    @AfterEach
    void stop() {
        logger.detachAppender(logs);
        server.stop(0);
    }

    GmailApiEmailService service(Clock clock) { return service(clock, CLIENT_ID, base + "/token", Duration.ofSeconds(2)); }

    GmailApiEmailService service(Clock clock, String clientId, String tokenUrl, Duration timeout) {
        var settings = new GmailApiEmailService.Settings(clientId, CLIENT_SECRET, REFRESH_TOKEN, "sender@example.test",
                tokenUrl, base, timeout, 5);
        return new GmailApiEmailService(settings, json, clock);
    }

    @Test
    void sendsOtpThroughGmailApiAndCachesAccessToken() throws Exception {
        var mail = service(Clock.systemUTC());
        mail.sendOtpEmail("customer@example.test", OTP, "LOGIN");
        mail.sendOtpEmail("customer@example.test", "777111", "SIGNUP");

        assertThat(tokenHits).hasValue(1);
        assertThat(sendHits).hasValue(2);
        Map<String, String> form = parseForm(tokenForms.getFirst());
        assertThat(form).containsEntry("grant_type", "refresh_token").containsEntry("client_id", CLIENT_ID)
                .containsEntry("client_secret", CLIENT_SECRET).containsEntry("refresh_token", REFRESH_TOKEN);
        assertThat(sendAuth).containsOnly("Bearer access-1");

        String mime = decodeRaw(sendBodies.getFirst());
        assertThat(mime).contains("To: customer@example.test").contains("From: sender@example.test")
                .contains("Subject: Digital Wallet verification LOGIN")
                .contains("Your verification code is " + OTP + ". It expires in 5 minutes. Do not share this code.");
        assertThat(decodeRaw(sendBodies.get(1))).contains("Subject: Digital Wallet verification SIGNUP").contains("777111");
        assertNoSecretsLogged();
    }

    @Test
    void refreshesAccessTokenWhenItIsAboutToExpire() {
        var clock = new MutableClock(Instant.parse("2026-11-05T00:00:00Z"));
        tokenBody = "{\"access_token\":\"access-1\",\"expires_in\":120}";
        var mail = service(clock);
        mail.sendOtpEmail("customer@example.test", OTP, "LOGIN");
        clock.now = clock.now.plusSeconds(30);
        mail.sendOtpEmail("customer@example.test", OTP, "LOGIN");
        assertThat(tokenHits).hasValue(1);
        clock.now = clock.now.plusSeconds(40); // within 60 s of expiry
        mail.sendOtpEmail("customer@example.test", OTP, "LOGIN");
        assertThat(tokenHits).hasValue(2);
        assertThat(sendAuth).containsExactly("Bearer access-1", "Bearer access-1", "Bearer access-2");
    }

    @Test
    void refreshesOnceAndRetriesWhenGmailRejectsTheAccessToken() {
        sendStatuses.addAll(List.of(401, 200));
        service(Clock.systemUTC()).sendOtpEmail("customer@example.test", OTP, "LOGIN");
        assertThat(tokenHits).hasValue(2);
        assertThat(sendAuth).containsExactly("Bearer access-1", "Bearer access-2");
    }

    @Test
    void secondRejectionIsReportedAsDeliveryUnavailable() {
        sendStatuses.addAll(List.of(401, 401));
        assertUnavailable(() -> service(Clock.systemUTC()).sendOtpEmail("customer@example.test", OTP, "LOGIN"));
        assertThat(sendHits).hasValue(2);
        assertNoSecretsLogged();
    }

    @Test
    void expiredRefreshTokenLogsOnlyTheOAuthErrorCode() {
        tokenStatus = 400;
        tokenBody = "{\"error\":\"invalid_grant\",\"error_description\":\"Token has been expired or revoked. " + REFRESH_TOKEN + "\"}";
        assertUnavailable(() -> service(Clock.systemUTC()).sendOtpEmail("customer@example.test", OTP, "LOGIN"));
        assertThat(sendHits).hasValue(0);
        assertThat(logText()).contains("HTTP 400").contains("invalid_grant").doesNotContain("expired or revoked");
        assertNoSecretsLogged();
    }

    @Test
    void gmailServerErrorIsDeliveryUnavailableWithoutRetry() {
        sendStatuses.add(500);
        assertUnavailable(() -> service(Clock.systemUTC()).sendOtpEmail("customer@example.test", OTP, "LOGIN"));
        assertThat(sendHits).hasValue(1);
        assertThat(logText()).contains("HTTP 500").doesNotContain("secret provider text");
        assertNoSecretsLogged();
    }

    @Test
    void slowGmailTimesOutAsDeliveryUnavailable() {
        sendDelayMs = 1500;
        var mail = service(Clock.systemUTC(), CLIENT_ID, base + "/token", Duration.ofMillis(500));
        assertUnavailable(() -> mail.sendOtpEmail("customer@example.test", OTP, "LOGIN"));
        assertNoSecretsLogged();
    }

    @Test
    void missingCredentialsOrInsecureUrlNeverCallTheNetwork() {
        assertUnavailable(() -> service(Clock.systemUTC(), " ", base + "/token", Duration.ofSeconds(2))
                .sendOtpEmail("customer@example.test", OTP, "LOGIN"));
        assertUnavailable(() -> service(Clock.systemUTC(), CLIENT_ID, "http://oauth2.example.test/token", Duration.ofSeconds(2))
                .sendOtpEmail("customer@example.test", OTP, "LOGIN"));
        assertThat(tokenHits).hasValue(0);
        assertThat(sendHits).hasValue(0);
        assertThat(GmailApiEmailService.secureUrl("https://oauth2.googleapis.com/token")).isTrue();
        assertThat(GmailApiEmailService.secureUrl("http://[::1]:9/token")).isTrue();
        assertThat(GmailApiEmailService.secureUrl("http://example.test/token")).isFalse();
        assertThat(GmailApiEmailService.secureUrl("")).isFalse();
        assertNoSecretsLogged();
    }

    @Test
    void providerSelectionAndMissingSettingNames() {
        assertThat(MailProviderConfig.normalized(" Gmail-API ")).isEqualTo("gmail-api");
        assertThat(MailProviderConfig.normalized(null)).isEqualTo("smtp");
        assertThat(MailProviderConfig.missingGmailSettings(CLIENT_ID, "", null))
                .containsExactly("GMAIL_CLIENT_SECRET", "GMAIL_REFRESH_TOKEN");
        assertThat(MailProviderConfig.missingGmailSettings(CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN)).isEmpty();
        var config = new MailProviderConfig();
        org.springframework.test.util.ReflectionTestUtils.setField(config, "provider", "sendgrid");
        assertThatThrownBy(() -> config.emailService(null, json)).isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("smtp or gmail-api");
    }

    private void assertUnavailable(org.assertj.core.api.ThrowableAssert.ThrowingCallable call) {
        assertThatThrownBy(call).isInstanceOfSatisfying(ApiException.class, ex -> {
            assertThat(ex.getStatus()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
            assertThat(ex.getCode()).isEqualTo("OTP_DELIVERY_UNAVAILABLE");
            assertThat(ex.getMessage()).doesNotContain(OTP);
        });
    }

    private void assertNoSecretsLogged() {
        assertThat(logText()).doesNotContain(OTP).doesNotContain(CLIENT_SECRET).doesNotContain(REFRESH_TOKEN)
                .doesNotContain("access-1").doesNotContain("customer@example.test");
    }

    private String logText() {
        return new ArrayList<>(logs.list).stream().map(ILoggingEvent::getFormattedMessage).collect(Collectors.joining("\n"));
    }

    private String decodeRaw(String body) throws Exception {
        String raw = json.readTree(body).path("raw").asText();
        byte[] bytes = Base64.getUrlDecoder().decode(raw);
        var message = new jakarta.mail.internet.MimeMessage(jakarta.mail.Session.getInstance(new java.util.Properties()),
                new ByteArrayInputStream(bytes));
        return new String(bytes, StandardCharsets.UTF_8) + "\n" + message.getContent();
    }

    private static Map<String, String> parseForm(String form) {
        return java.util.Arrays.stream(form.split("&")).map(p -> p.split("=", 2))
                .collect(Collectors.toMap(p -> URLDecoder.decode(p[0], StandardCharsets.UTF_8),
                        p -> URLDecoder.decode(p[1], StandardCharsets.UTF_8)));
    }

    static final class MutableClock extends Clock {
        volatile Instant now;
        MutableClock(Instant now) { this.now = now; }
        @Override public ZoneOffset getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(java.time.ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    }
}
