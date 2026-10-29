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
    @MockitoBean TelegramOidcClient telegram;
    final HttpClient http = HttpClient.newHttpClient();
    final Map<String,String> receipts = new HashMap<>();
    @DynamicPropertySource static void telegramProperties(DynamicPropertyRegistry r) {
        r.add("app.telegram.client-id", () -> "12345");
        r.add("app.telegram.client-secret", () -> "test-only-secret");
        r.add("app.telegram.redirect-uri", () -> "https://bank.example.test/api/v1/auth/telegram/callback");
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
}
