package com.bank.digital_banking;

import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.auth.repository.TelegramLoginFlowRepository;
import com.bank.digital_banking.module.auth.service.TelegramOidcClient;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import tools.jackson.databind.*;

import java.net.*;
import java.net.http.*;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

class ContinuationAuthTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired UserRepository users;
    @Autowired TelegramLoginFlowRepository flows;
    @Autowired com.bank.digital_banking.module.auth.repository.AuthSessionRepository sessions;
    @Autowired com.bank.digital_banking.module.auth.repository.OtpRateLimitRepository otpLimits;
    @MockitoBean TelegramOidcClient telegram;
    final HttpClient http = HttpClient.newHttpClient();
    final Map<String,String> receipts = new HashMap<>();
    @DynamicPropertySource static void telegramProperties(DynamicPropertyRegistry r) {
        r.add("app.telegram.client-id", () -> "12345");
        r.add("app.telegram.client-secret", () -> "test-only-secret");
        r.add("app.telegram.redirect-uri", () -> "https://bank.example.test/api/v1/auth/telegram/callback");
        r.add("app.telegram.native-redirect-uri", () -> "https://app937652339-login.tg.dev/tglogin");
    }
    @BeforeEach void prepare() { SMTP.reset(); }
    Map<String,Object> device() { return Map.of("deviceFingerprint", "continue-" + UUID.randomUUID(), "deviceName", "Browser", "deviceType", "WEB"); }
    String email() { return "continue-" + UUID.randomUUID() + "@example.test"; }
    HttpResponse<String> call(String method, String path, String token, Object body) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1/auth" + path));
        if (token != null) request.header("Authorization", "Bearer " + token);
        if (body != null) request.header("Content-Type", "application/json");
        request.method(method, body == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body)));
        return http.send(request.build(), HttpResponse.BodyHandlers.ofString());
    }
    JsonNode data(HttpResponse<String> response) throws Exception {
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        assertThat(response.headers().firstValue("Cache-Control").orElse("")).contains("no-store");
        return json.readTree(response.body()).path("data");
    }
    JsonNode continueEmail(String email) throws Exception {
        data(call("POST", "/email/request", null, Map.of("email", email)));
        var body = new HashMap<String,Object>(device()); body.put("email", email); body.put("otpCode", SMTP.code(email));
        return data(call("POST", "/email/verify", null, body));
    }
    JsonNode completedEmail(String email) throws Exception {
        JsonNode tokens = continueEmail(email);
        data(call("PATCH", "/profile", tokens.path("accessToken").asText(), Map.of("firstName", "Pin", "lastName", "Customer")));
        return tokens;
    }
    void continueCooldownElapsed(String email) {
        // Advance only this isolated fixture's persisted cooldown; production limits stay enabled.
        var limit = otpLimits.findById(email + "|CONTINUE").orElseThrow();
        limit.setLastRequestedAt(java.time.OffsetDateTime.now().minusSeconds(61));
        otpLimits.save(limit);
    }
    JsonNode pinPrepare(JsonNode tokens) throws Exception {
        return data(call("POST", "/pin/prepare", tokens.path("accessToken").asText(), null));
    }
    JsonNode pinSetup(String ticket, String pin, boolean reset) throws Exception {
        return data(call("POST", "/pin/setup", null, Map.of("ticket", ticket, "pin", pin, "confirmPin", pin, "reset", reset)));
    }
    int accounts(String access) throws Exception {
        return http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1/accounts/me"))
                .header("Authorization", "Bearer " + access).GET().build(), HttpResponse.BodyHandlers.ofString()).statusCode();
    }
    @Test void pinSetupBlocksBankingAndRefreshAndOldAccessCannotSurviveAnUnlock() throws Exception {
        JsonNode tokens = completedEmail(email());
        String access = tokens.path("accessToken").asText();
        JsonNode challenge = pinPrepare(tokens);
        String ticket = challenge.path("ticket").asText();
        assertThat(challenge.path("configured").asBoolean()).isFalse();
        assertThat(accounts(access)).isEqualTo(403);
        assertThat(call("POST", "/refresh", null, Map.of("refreshToken", tokens.path("refreshToken").asText())).statusCode()).isEqualTo(403);
        assertThat(call("POST", "/pin/setup", null, Map.of("ticket", ticket, "pin", "0427", "confirmPin", "0428")).statusCode()).isEqualTo(400);
        JsonNode unlocked = pinSetup(ticket, "0427", false);
        assertThat(accounts(unlocked.path("accessToken").asText())).isEqualTo(200);
        assertThat(accounts(access)).isEqualTo(403);
        data(call("POST", "/pin/status", null, Map.of("ticket", ticket)));
        assertThat(accounts(unlocked.path("accessToken").asText())).isEqualTo(403);
        JsonNode again = data(call("POST", "/pin/unlock", null, Map.of("ticket", ticket, "pin", "0427")));
        assertThat(accounts(again.path("accessToken").asText())).isEqualTo(200);
        assertThat(accounts(unlocked.path("accessToken").asText())).isEqualTo(403);
    }
    @Test void fiveWrongPinsPersistAcrossReopensAndNewLoginsUntilVerifiedRecovery() throws Exception {
        String email = email();
        String ticket = pinPrepare(completedEmail(email)).path("ticket").asText();
        pinSetup(ticket, "8316", false);
        for (int i = 1; i <= 5; i++) {
            var wrong = call("POST", "/pin/unlock", null, Map.of("ticket", ticket, "pin", "9999"));
            assertThat(wrong.statusCode()).isEqualTo(403);
            assertThat(json.readTree(wrong.body()).path("error").asText()).isEqualTo(i == 5 ? "PIN_RECOVERY_REQUIRED" : "PIN_INVALID");
            JsonNode state = data(call("POST", "/pin/status", null, Map.of("ticket", ticket)));
            assertThat(state.path("attemptsRemaining").asInt()).isEqualTo(5 - i);
        }
        assertThat(call("POST", "/pin/unlock", null, Map.of("ticket", ticket, "pin", "8316")).statusCode()).isEqualTo(403);
        assertThat(call("POST", "/pin/setup", null, Map.of("ticket", ticket, "pin", "1234", "confirmPin", "1234", "reset", true)).statusCode()).isEqualTo(403);
        continueCooldownElapsed(email);
        JsonNode recovery = pinPrepare(continueEmail(email));
        assertThat(recovery.path("recoveryRequired").asBoolean()).isTrue();
        assertThat(recovery.path("canRecover").asBoolean()).isTrue();
        String freshTicket = recovery.path("ticket").asText();
        JsonNode fresh = pinSetup(freshTicket, "5072", true);
        assertThat(accounts(fresh.path("accessToken").asText())).isEqualTo(200);
        assertThat(call("POST", "/pin/status", null, Map.of("ticket", ticket)).statusCode()).isEqualTo(401);
        assertThat(data(call("POST", "/pin/status", null, Map.of("ticket", freshTicket))).path("attemptsRemaining").asInt()).isEqualTo(5);
        assertThat(call("POST", "/pin/unlock", null, Map.of("ticket", freshTicket, "pin", "8316")).statusCode()).isEqualTo(403);
        assertThat(data(call("POST", "/pin/unlock", null, Map.of("ticket", freshTicket, "pin", "5072"))).has("accessToken")).isTrue();
    }
    @Test void concurrentPinGuessesCannotExceedTheServerAttemptBudget() throws Exception {
        String ticket = pinPrepare(completedEmail(email())).path("ticket").asText();
        pinSetup(ticket, "7352", false);
        var requests = new ArrayList<java.util.concurrent.CompletableFuture<HttpResponse<String>>>();
        for (int i = 0; i < 8; i++) requests.add(java.util.concurrent.CompletableFuture.supplyAsync(() -> {
            try { return call("POST", "/pin/unlock", null, Map.of("ticket", ticket, "pin", "0000")); }
            catch (Exception ex) { throw new java.util.concurrent.CompletionException(ex); }
        }));
        for (var request : requests) assertThat(request.get().statusCode()).isEqualTo(403);
        JsonNode state = data(call("POST", "/pin/status", null, Map.of("ticket", ticket)));
        assertThat(state.path("attemptsRemaining").asInt()).isZero();
        assertThat(state.path("recoveryRequired").asBoolean()).isTrue();
    }
    @Test void pinRecoveryRequiresFreshIdentityAndCannotUseAnUnlockedOrOldSession() throws Exception {
        String email = email();
        String ticket = pinPrepare(completedEmail(email)).path("ticket").asText();
        JsonNode unlocked = pinSetup(ticket, "6453", false);
        assertThat(data(call("POST", "/pin/status", null, Map.of("ticket", ticket))).path("canRecover").asBoolean()).isFalse();
        assertThat(call("POST", "/pin/setup", null, Map.of("ticket", ticket, "pin", "3232", "confirmPin", "3232", "reset", true)).statusCode()).isEqualTo(403);
        continueCooldownElapsed(email);
        JsonNode fresh = continueEmail(email);
        UUID sid = UUID.fromString(data(call("GET", "/me", fresh.path("accessToken").asText(), null)).path("sessionId").asText());
        var session = sessions.findById(sid).orElseThrow(); session.setCreatedAt(java.time.OffsetDateTime.now().minusMinutes(11)); sessions.save(session);
        String stale = pinPrepare(fresh).path("ticket").asText();
        assertThat(call("POST", "/pin/setup", null, Map.of("ticket", stale, "pin", "3232", "confirmPin", "3232", "reset", true)).statusCode()).isEqualTo(403);
        assertThat(data(call("POST", "/pin/unlock", null, Map.of("ticket", stale, "pin", "6453"))).has("accessToken")).isTrue();
        data(call("POST", "/pin/discard", null, Map.of("ticket", stale)));
        assertThat(call("POST", "/pin/status", null, Map.of("ticket", stale)).statusCode()).isEqualTo(401);
        assertThat(call("POST", "/pin/status", null, Map.of("ticket", "forged-ticket")).statusCode()).isEqualTo(401);
    }
    @Test void pinCannotBeCreatedBeforeProfileCompletionAndInvalidFormatsDoNotConsumeAttempts() throws Exception {
        JsonNode pending = continueEmail(email());
        assertThat(call("POST", "/pin/prepare", pending.path("accessToken").asText(), null).statusCode()).isEqualTo(403);
        assertThat(call("POST", "/pin/prepare", null, null).statusCode()).isEqualTo(401);
        String ticket = pinPrepare(completedEmail(email())).path("ticket").asText();
        pinSetup(ticket, "0007", false);
        for (String invalid : List.of("", "123", "12345", "abcd"))
            assertThat(call("POST", "/pin/unlock", null, Map.of("ticket", ticket, "pin", invalid)).statusCode()).isEqualTo(400);
        assertThat(data(call("POST", "/pin/status", null, Map.of("ticket", ticket))).path("attemptsRemaining").asInt()).isEqualTo(5);
    }
    @Test void initialPinEnrollmentCannotUseAnOldIdentityOrAnAgedTicket() throws Exception {
        for (boolean prepareFirst : List.of(false, true)) {
            JsonNode tokens = completedEmail(email());
            String ticket = prepareFirst ? pinPrepare(tokens).path("ticket").asText() : null;
            var session = sessions.findById(UUID.fromString(tokens.path("sessionId").asText())).orElseThrow();
            session.setCreatedAt(java.time.OffsetDateTime.now().minusMinutes(11));
            sessions.save(session);
            if (prepareFirst) {
                assertThat(call("POST", "/pin/setup", null, Map.of("ticket", ticket, "pin", "0427", "confirmPin", "0427")).statusCode()).isEqualTo(403);
                assertThat(call("POST", "/pin/status", null, Map.of("ticket", ticket)).statusCode()).isEqualTo(401);
            } else {
                assertThat(call("POST", "/pin/prepare", tokens.path("accessToken").asText(), null).statusCode()).isEqualTo(403);
            }
        }
    }
    HttpResponse<String> photoUpload(String token, byte[] image) throws Exception {
        String boundary = "kesor-photo-test";
        var bytes = new java.io.ByteArrayOutputStream();
        bytes.write(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"untrusted.svg\"\r\nContent-Type: image/png\r\n\r\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
        bytes.write(image);
        bytes.write(("\r\n--" + boundary + "--\r\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
        var request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1/auth/profile/photo"))
                .header("Content-Type", "multipart/form-data; boundary=" + boundary);
        if (token != null) request.header("Authorization", "Bearer " + token);
        return http.send(request.PUT(HttpRequest.BodyPublishers.ofByteArray(bytes.toByteArray())).build(), HttpResponse.BodyHandlers.ofString());
    }
    byte[] photo(String format, int width) throws Exception {
        var image = new java.awt.image.BufferedImage(width, 2, java.awt.image.BufferedImage.TYPE_INT_RGB);
        image.setRGB(0, 0, 0x123358);
        var output = new java.io.ByteArrayOutputStream();
        javax.imageio.ImageIO.write(image, format, output);
        return output.toByteArray();
    }
    @Test void privatePhotoPersistsAcrossSessionsAndNeverCrossesCustomers() throws Exception {
        String email = email();
        JsonNode tokens = continueEmail(email);
        String access = tokens.path("accessToken").asText();
        assertThat(data(call("GET", "/profile/photo", access, null)).isMissingNode()).isTrue();
        JsonNode saved = data(photoUpload(access, photo("png", 2)));
        assertThat(saved.path("contentType").asText()).isEqualTo("image/png");
        assertThat(data(call("GET", "/profile/photo", access, null))).isEqualTo(saved);
        String other = continueEmail(email()).path("accessToken").asText();
        assertThat(data(call("GET", "/profile/photo", other, null)).isMissingNode()).isTrue();
        JsonNode renewed = data(call("POST", "/refresh", null, Map.of("refreshToken", tokens.path("refreshToken").asText())));
        assertThat(data(call("GET", "/profile/photo", renewed.path("accessToken").asText(), null))).isEqualTo(saved);
        assertThat(data(call("GET", "/me", access, null)).path("profileComplete").asBoolean()).isFalse();
        assertThat(photoUpload(null, photo("png", 2)).statusCode()).isEqualTo(401);
        assertThat(call("GET", "/profile/photo", null, null).statusCode()).isEqualTo(401);
        assertThat(call("GET", "/profile/photo?userId=" + users.findByEmail(email).orElseThrow().getId(), other, null).body())
                .doesNotContain(saved.path("imageBase64").asText());
    }
    @Test void photoValidationRejectsSpoofedEmptyOversizedAndMalformedImagesWithoutReplacingExisting() throws Exception {
        String access = continueEmail(email()).path("accessToken").asText();
        JsonNode saved = data(photoUpload(access, photo("png", 2)));
        for (byte[] invalid : List.of(new byte[0], "<svg><script>alert(1)</script></svg>".getBytes(), photo("gif", 2), new byte[]{1,2,3})) {
            var response = photoUpload(access, invalid);
            assertThat(response.statusCode()).as(response.body()).isEqualTo(400);
            assertThat(json.readTree(response.body()).path("error").asText()).isEqualTo("PROFILE_PHOTO_INVALID");
        }
        var oversized = photoUpload(access, new byte[5 * 1024 * 1024 + 1]);
        assertThat(oversized.statusCode()).as(oversized.body()).isEqualTo(413);
        assertThat(json.readTree(oversized.body()).path("error").asText()).isEqualTo("PROFILE_PHOTO_TOO_LARGE");
        assertThat(data(call("GET", "/profile/photo", access, null))).isEqualTo(saved);
    }
    @Test void photoUsesDecodedFormatAndNormalizesDimensionsInsteadOfTrustingFilenameOrMime() throws Exception {
        String access = continueEmail(email()).path("accessToken").asText();
        JsonNode saved = data(photoUpload(access, photo("jpeg", 2400)));
        assertThat(saved.path("contentType").asText()).isEqualTo("image/jpeg");
        var decoded = javax.imageio.ImageIO.read(new java.io.ByteArrayInputStream(Base64.getDecoder().decode(saved.path("imageBase64").asText())));
        assertThat(decoded.getWidth()).isEqualTo(1024);
        assertThat(decoded.getHeight()).isEqualTo(1);
        byte[] hugeHeader = photo("png", 2);
        java.nio.ByteBuffer.wrap(hugeHeader, 16, 8).putInt(100_000).putInt(100_000);
        var crc = new java.util.zip.CRC32(); crc.update(hugeHeader, 12, 17);
        java.nio.ByteBuffer.wrap(hugeHeader, 29, 4).putInt((int) crc.getValue());
        assertThat(photoUpload(access, hugeHeader).statusCode()).isEqualTo(400);
    }
    @Test void emailCreatesOnlyAfterVerificationAndOnboardingIsEnforcedAndResumable() throws Exception {
        String email = email();
        data(call("POST", "/email/request", null, Map.of("email", email)));
        assertThat(users.existsByEmail(email)).isFalse();
        var payload = new HashMap<String,Object>(device()); payload.put("email", email); payload.put("otpCode", SMTP.code(email));
        JsonNode tokens = data(call("POST", "/email/verify", null, payload));
        String access = tokens.path("accessToken").asText();
        assertThat(data(call("GET", "/me", access, null)).path("profileComplete").asBoolean()).isFalse();
        var bank = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1/accounts/me"))
                .header("Authorization", "Bearer " + access).GET().build();
        assertThat(http.send(bank, HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(403);
        assertThat(call("POST", "/email/verify", null, payload).statusCode()).isEqualTo(401);
        JsonNode refreshed = data(call("POST", "/refresh", null, Map.of("refreshToken", tokens.path("refreshToken").asText())));
        access = refreshed.path("accessToken").asText();
        assertThat(data(call("GET", "/me", access, null)).path("profileComplete").asBoolean()).isFalse();
        assertThat(data(call("PATCH", "/profile", access, Map.of("firstName", " Dara ", "lastName", "Sok")))
                .path("profileComplete").asBoolean()).isTrue();
        bank = HttpRequest.newBuilder(bank.uri()).header("Authorization", "Bearer " + access).GET().build();
        assertThat(http.send(bank, HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(200);
        User user = users.findByEmail(email).orElseThrow();
        assertThat(user.getFirstName()).isEqualTo("Dara"); assertThat(user.getPassword()).isNull();
        assertThat(data(call("PATCH", "/profile", access, Map.of("firstName", "Changed", "lastName", "Name")))
                .path("firstName").asText()).isEqualTo("Dara");
    }
    @Test void returningCustomerKeepsTheirIdentityAndDoesNotRepeatOnboarding() throws Exception {
        JsonNode result = continueEmail("alice.demo@example.test");
        JsonNode me = data(call("GET", "/me", result.path("accessToken").asText(), null));
        assertThat(me.path("username").asText()).isEqualTo("alice.demo");
        assertThat(me.path("profileComplete").asBoolean()).isTrue();
    }
    @Test void staffCannotUseCustomerPasswordlessContinuation() throws Exception {
        String email = "employee.demo@example.test";
        data(call("POST", "/email/request", null, Map.of("email", email)));
        var body = new HashMap<String,Object>(device()); body.put("email", email); body.put("otpCode", SMTP.code(email));
        assertThat(call("POST", "/email/verify", null, body).statusCode()).isEqualTo(401);
    }
    JsonNode start() throws Exception { return data(call("POST", "/telegram/start", null, device())); }
    Map<String,String> exchangeBody(JsonNode start) {
        var body = new HashMap<>(Map.of("flowId", start.path("flowId").asText(), "exchangeSecret", start.path("exchangeSecret").asText()));
        String receipt = receipts.get(start.path("flowId").asText());
        if (receipt != null) body.put("approvalReceipt", receipt);
        return body;
    }
    void rememberReceipt(HttpResponse<String> response) throws Exception {
        String marker = "window.opener.postMessage(";
        int begin = response.body().indexOf(marker) + marker.length();
        int end = response.body().indexOf(",\"http", begin);
        assertThat(end).isGreaterThan(begin);
        JsonNode payload = json.readTree(json.readValue(response.body().substring(begin, end), String.class));
        receipts.put(payload.path("flowId").asText(), payload.path("approvalReceipt").asText());
    }
    void callback(JsonNode start) throws Exception {
        var response = call("GET", "/telegram/callback?state=" + start.path("flowId").asText() + "&code=test-code", null, null);
        assertThat(response.statusCode()).isEqualTo(200);
        rememberReceipt(response);
    }
    @Test void telegramNeedsNoAppOtpAndExchangeIsBoundAndOneUse() throws Exception {
        when(telegram.authenticateCode(anyString(), anyString(), anyString())).thenReturn(new TelegramOidcClient.Identity("subject-" + UUID.randomUUID(), "Dara", "Sok"));
        JsonNode start = start();
        assertThat(start.path("authorizationUrl").asText()).contains("code_challenge_method=S256", "nonce=");
        assertThat(data(call("POST", "/telegram/exchange", null, exchangeBody(start))).path("status").asText()).isEqualTo("PENDING");
        callback(start);
        assertThat(data(call("POST", "/telegram/exchange", null, Map.of("flowId", start.path("flowId").asText(),
                "exchangeSecret", start.path("exchangeSecret").asText()))).path("status").asText()).isEqualTo("PENDING");
        var wrongReceipt = new HashMap<>(exchangeBody(start)); wrongReceipt.put("approvalReceipt", "Y".repeat(43));
        assertThat(call("POST", "/telegram/exchange", null, wrongReceipt).statusCode()).isEqualTo(401);
        assertThat(call("POST", "/telegram/exchange", null, Map.of("flowId", start.path("flowId").asText(), "exchangeSecret", "X".repeat(43))).statusCode()).isEqualTo(401);
        JsonNode result = data(call("POST", "/telegram/exchange", null, exchangeBody(start)));
        assertThat(result.path("status").asText()).isEqualTo("COMPLETE");
        JsonNode me = data(call("GET", "/me", result.path("tokens").path("accessToken").asText(), null));
        assertThat(me.path("email").isNull()).isTrue();
        assertThat(me.path("telegramLinked").asBoolean()).isTrue();
        assertThat(me.path("profileComplete").asBoolean()).isFalse();
        assertThat(call("POST", "/telegram/exchange", null, exchangeBody(start)).statusCode()).isEqualTo(401);
        assertThat(call("GET", "/telegram/callback?state=" + start.path("flowId").asText() + "&code=replay", null, null).statusCode()).isEqualTo(400);
    }
    @Test void cancelledAndExpiredTelegramFlowsDoNotCreateSessions() throws Exception {
        JsonNode start = start();
        data(call("POST", "/telegram/exchange", null, exchangeBody(start)));
        rememberReceipt(call("GET", "/telegram/callback?state=" + start.path("flowId").asText() + "&error=access_denied", null, null));
        assertThat(data(call("POST", "/telegram/exchange", null, exchangeBody(start))).path("status").asText()).isEqualTo("TELEGRAM_CANCELLED");
        var flow = flows.findById(start.path("flowId").asText()).orElseThrow();
        flow.setExpiresAt(java.time.OffsetDateTime.now().minusSeconds(1)); flows.save(flow);
        assertThat(call("POST", "/telegram/exchange", null, exchangeBody(start)).statusCode()).isEqualTo(401);
    }
    @Test void verifiedEmailCanConnectOnboardingTelegramToExistingCustomerWithoutDuplicatingBankingData() throws Exception {
        String subject = "link-" + UUID.randomUUID();
        when(telegram.authenticateCode(anyString(), anyString(), anyString())).thenReturn(new TelegramOidcClient.Identity(subject, "Dara", "Sok"));
        JsonNode start = start(); callback(start);
        JsonNode tokens = data(call("POST", "/telegram/exchange", null, exchangeBody(start))).path("tokens");
        String access = tokens.path("accessToken").asText();
        String email = "bob.demo@example.test";
        data(call("POST", "/email/link/request", access, Map.of("email", email)));
        var payload = new HashMap<String,Object>(device()); payload.put("email", email); payload.put("otpCode", SMTP.code(email));
        JsonNode linked = data(call("POST", "/email/link/verify", access, payload));
        assertThat(linked.path("userId").asLong()).isEqualTo(users.findByEmail(email).orElseThrow().getId());
        assertThat(users.findByTelegramSubject(subject).orElseThrow().getUsername()).isEqualTo("bob.demo");
        assertThat(call("GET", "/me", access, null).statusCode()).isEqualTo(401);
    }

    @Test void emailCustomerCanLinkTelegramAndRequiresFreshAuthentication() throws Exception {
        JsonNode customer = continueEmail(email());
        String access = customer.path("accessToken").asText();
        String subject = "email-link-" + UUID.randomUUID();
        when(telegram.authenticateCode(anyString(), anyString(), anyString())).thenReturn(new TelegramOidcClient.Identity(subject, "Dara", "Sok"));
        assertThat(call("POST", "/telegram/link/start", null, device()).statusCode()).isEqualTo(401);
        JsonNode start = data(call("POST", "/telegram/link/start", access, device())); callback(start);
        JsonNode linked = data(call("POST", "/telegram/exchange", null, exchangeBody(start))).path("tokens");
        assertThat(linked.path("userId")).isEqualTo(customer.path("userId"));
        var session = sessions.findById(UUID.fromString(linked.path("sessionId").asText())).orElseThrow();
        session.setCreatedAt(java.time.OffsetDateTime.now().minusMinutes(11)); sessions.save(session);
        assertThat(call("POST", "/telegram/link/start", linked.path("accessToken").asText(), device()).statusCode()).isEqualTo(403);
    }

    @Test void linkingEmailCodeCannotAuthorizeAnonymousEmailContinuation() throws Exception {
        JsonNode owner = continueEmail(email()); String access = owner.path("accessToken").asText();
        String recovery = email();
        data(call("POST", "/email/link/request", access, Map.of("email", recovery)));
        var payload = new HashMap<String,Object>(device()); payload.put("email", recovery); payload.put("otpCode", SMTP.code(recovery));
        assertThat(call("POST", "/email/verify", null, payload).statusCode()).isEqualTo(401);
        assertThat(users.existsByEmail(recovery)).isFalse();
    }

    JsonNode nativeStart() throws Exception { return data(call("POST", "/telegram/native/start", null, device())); }
    Map<String,String> nativeExchange(JsonNode start) {
        return Map.of("flowId", start.path("flowId").asText(), "exchangeSecret", start.path("exchangeSecret").asText(), "code", "native-test-code");
    }
    @Test void nativeApprovalIsBoundSeparatedFromBrowserAndConsumedOnce() throws Exception {
        String subject = "native-" + UUID.randomUUID();
        when(telegram.authenticateNativeCode(anyString(), anyString(), anyString(), anyString()))
                .thenReturn(new TelegramOidcClient.Identity(subject, "Dara", "Sok"));
        JsonNode start = nativeStart();
        var flow = flows.findById(start.path("flowId").asText()).orElseThrow();
        assertThat(flow.isNativeFlow()).isTrue();
        assertThat(start.path("redirectUri").asText()).isEqualTo("https://app937652339-login.tg.dev/tglogin");
        assertThat(start.path("authorizationUrl").asText()).contains("nonce=" + flow.getNonce(), "state=" + flow.getId(), "code_challenge_method=S256");
        assertThat(start.toString()).doesNotContain(flow.getVerifier(), "test-only-secret");
        assertThat(users.findByTelegramSubject(subject)).isEmpty();
        assertThat(call("POST", "/telegram/exchange", null, exchangeBody(start)).statusCode()).isEqualTo(401);
        assertThat(call("GET", "/telegram/callback?state=" + flow.getId() + "&code=wrong-channel", null, null).statusCode()).isEqualTo(400);
        var wrong = new HashMap<>(nativeExchange(start)); wrong.put("exchangeSecret", "Z".repeat(43));
        assertThat(call("POST", "/telegram/native/exchange", null, wrong).statusCode()).isEqualTo(401);
        assertThat(flows.findById(flow.getId()).orElseThrow().isClaimed()).isFalse();
        JsonNode tokens = data(call("POST", "/telegram/native/exchange", null, nativeExchange(start)));
        String access = tokens.path("accessToken").asText();
        JsonNode me = data(call("GET", "/me", access, null));
        assertThat(me.path("telegramLinked").asBoolean()).isTrue();
        assertThat(me.path("email").isNull()).isTrue();
        assertThat(me.path("profileComplete").asBoolean()).isFalse();
        assertThat(call("POST", "/telegram/native/exchange", null, nativeExchange(start)).statusCode()).isEqualTo(401);
        org.mockito.Mockito.verify(telegram).authenticateNativeCode("native-test-code", flow.getVerifier(), flow.getNonce(), flow.getRedirectUri());
        var bank = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1/accounts/me"))
                .header("Authorization", "Bearer " + access).GET().build();
        assertThat(http.send(bank, HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(403);
    }
    @Test void nativeExchangeFailureIsConsumedEvenWhenTelegramIsUnavailable() throws Exception {
        when(telegram.authenticateNativeCode(anyString(), anyString(), anyString(), anyString()))
                .thenThrow(new com.bank.digital_banking.common.exception.ApiException(org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE,
                        "TELEGRAM_UNAVAILABLE", "Unavailable"));
        JsonNode start = nativeStart();
        long count = sessions.count();
        assertThat(call("POST", "/telegram/native/exchange", null, nativeExchange(start)).statusCode()).isEqualTo(503);
        assertThat(call("POST", "/telegram/native/exchange", null, nativeExchange(start)).statusCode()).isEqualTo(401);
        assertThat(sessions.count()).isEqualTo(count);
        assertThat(flows.findById(start.path("flowId").asText()).orElseThrow().isClaimed()).isTrue();
    }
    @Test void nativeExchangeRejectsBrowserFlowsAndExpiredNativeFlows() throws Exception {
        JsonNode browser = start();
        assertThat(call("POST", "/telegram/native/exchange", null, nativeExchange(browser)).statusCode()).isEqualTo(401);
        JsonNode start = nativeStart();
        var flow = flows.findById(start.path("flowId").asText()).orElseThrow();
        flow.setExpiresAt(java.time.OffsetDateTime.now().minusSeconds(1)); flows.save(flow);
        assertThat(call("POST", "/telegram/native/exchange", null, nativeExchange(start)).statusCode()).isEqualTo(401);
    }
    @Test void nativeLinkingKeepsExistingCustomerAndRequiresFreshAuthentication() throws Exception {
        assertThat(call("POST", "/telegram/native/link/start", null, device()).statusCode()).isEqualTo(401);
        JsonNode customer = continueEmail(email());
        String subject = "native-link-" + UUID.randomUUID();
        when(telegram.authenticateNativeCode(anyString(), anyString(), anyString(), anyString()))
                .thenReturn(new TelegramOidcClient.Identity(subject, "Dara", "Sok"));
        JsonNode start = data(call("POST", "/telegram/native/link/start", customer.path("accessToken").asText(), device()));
        JsonNode linked = data(call("POST", "/telegram/native/exchange", null, nativeExchange(start)));
        assertThat(linked.path("userId")).isEqualTo(customer.path("userId"));
        var session = sessions.findById(UUID.fromString(linked.path("sessionId").asText())).orElseThrow();
        session.setCreatedAt(java.time.OffsetDateTime.now().minusMinutes(11)); sessions.save(session);
        assertThat(call("POST", "/telegram/native/link/start", linked.path("accessToken").asText(), device()).statusCode()).isEqualTo(403);
    }
}
