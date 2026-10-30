package com.bank.digital_banking;

import com.bank.digital_banking.module.auth.repository.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;

/** Executes the published examples against isolated PostgreSQL and real local SMTP. */
class FoundationReadinessTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired OtpRepository otps;
    @Autowired OtpRateLimitRepository otpLimits;
    @Autowired LoginAttemptLimitRepository loginLimits;
    @Autowired UserRepository users;
    @Autowired JdbcTemplate jdbc;
    final HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    @BeforeEach void resetLimits() {
        otps.deleteAll();
        otpLimits.deleteAll();
        loginLimits.deleteAll();
        SMTP.reset();
    }

    @Test void schemasAcceptActualNullableErrorAndOptionalValues() throws Exception {
        for (String document : List.of("/v3/api-docs", "/v3/api-docs/foundation")) {
            JsonNode api = body(call("GET", document, null, null, null));
            for (var fields : Map.of("ApiErrorResponse", List.of("retryAfterSeconds"),
                    "RegisterRequestDto", List.of("firstName", "lastName", "deviceType"),
                    "LoginRequestDto", List.of("deviceType"), "TransferRequestDto", List.of("remark"),
                    "DepositRequestDto", List.of("remark"),
                    "TransactionResponseDto", List.of("sourceAccountNumber", "destinationAccountNumber", "remark")).entrySet())
                for (String field : fields.getValue()) {
                    JsonNode property = api.path("components").path("schemas").path(fields.getKey())
                            .path("properties").path(field);
                    assertThat(property.path("type").toString()).as(fields.getKey() + "." + field).contains("null");
                }
        }
        var rejected = call("GET", "/api/v1/auth/me", null, null, null);
        assertThat(rejected.statusCode()).isEqualTo(401);
        assertThat(body(rejected).path("retryAfterSeconds").isNull()).isTrue();
    }

    @Test void readOnlyAndIdentityContractsIncludeAuditUnavailableResponses() throws Exception {
        JsonNode api = body(call("GET", "/v3/api-docs/foundation", null, null, null));
        for (String path : List.of("/auth/me", "/accounts/me", "/accounts/{accountNumber}",
                "/transactions/account/{accountNumber}", "/transactions/{referenceNumber}")) {
            JsonNode response = operation(api, path, "get").path("responses").path("503");
            assertThat(response.path("content").path("application/json").path("example").path("error").asText())
                    .isEqualTo("AUDIT_UNAVAILABLE");
        }
        jdbc.execute("alter table audit_logs add constraint f1_qa_audit_unavailable check (false) not valid");
        try {
            var unavailable = call("GET", "/api/v1/auth/me", null, null, null);
            assertThat(unavailable.statusCode()).isEqualTo(503);
            assertThat(body(unavailable).path("error").asText()).isEqualTo("AUDIT_UNAVAILABLE");
        } finally {
            jdbc.execute("alter table audit_logs drop constraint f1_qa_audit_unavailable");
        }
    }

    @Test void generatedContractsShowPublicAuthRealStatusesAndFoundationOnlyGroup() throws Exception {
        for (String document : List.of("/v3/api-docs", "/v3/api-docs/foundation")) {
            JsonNode api = body(call("GET", document, null, null, null));
            assertThat(api.path("security").get(0).has("bearerAuth")).isTrue();
            for (String path : List.of("request-otp", "register", "login", "refresh", "email/request", "email/verify", "telegram/start", "telegram/exchange")) {
                JsonNode security = operation(api, "/auth/" + path, "post").path("security");
                assertThat(security.isArray()).isTrue();
                assertThat(security.size()).isZero();
            }
            assertThat(operation(api, "/auth/me", "get").has("security")).isFalse();
            JsonNode registration = operation(api, "/auth/register", "post").path("responses");
            assertThat(registration.has("201")).isTrue();
            assertThat(registration.has("200")).isFalse();
            assertThat(registration.path("201").path("content").path("application/json")
                    .path("schema").path("$ref").asText()).contains("TokenResponseDto");
            assertThat(operation(api, "/accounts", "post").path("responses").has("201")).isTrue();
            JsonNode throttle = operation(api, "/auth/request-otp", "post").path("responses").path("429");
            assertThat(throttle.path("headers").has("Retry-After")).isTrue();
            assertThat(throttle.path("content").path("application/json").path("schema").path("$ref").asText())
                    .isEqualTo("#/components/schemas/ApiErrorResponse");
            assertThat(api.path("components").path("schemas").path("ApiErrorResponse")
                    .path("properties").has("retryAfterSeconds")).isTrue();
            for (String path : List.of("transfer", "deposit")) {
                boolean required = false;
                for (JsonNode parameter : operation(api, "/transactions/" + path, "post").path("parameters"))
                    if (parameter.path("name").asText().equals("Idempotency-Key"))
                        required = parameter.path("required").asBoolean();
                assertThat(required).isTrue();
            }
            if (document.endsWith("foundation")) {
                assertThat(api.path("paths").size()).isEqualTo(35);
                assertThat(api.path("paths").has("/api/v1/payments/khqr/generate")).isFalse();
                assertThat(api.path("paths").has("/api/v1/ai/chat")).isFalse();
                assertThat(api.path("paths").has("/api/v1/fraud/check")).isFalse();
            }
        }
        assertThat(call("GET", "/swagger-ui/index.html", null, null, null).statusCode()).isEqualTo(200);
        assertThat(call("GET", "/api/v1/auth/me", null, null, null).statusCode()).isEqualTo(401);
    }

    @Test void publishedExamplesCompleteTheCoreWorkflowAndEnforceRoleBoundaries() throws Exception {
        JsonNode api = body(call("GET", "/v3/api-docs/foundation", null, null, null));
        for (String name : List.of("alice.demo", "bob.demo", "empty.demo", "employee.demo"))
            assertThat(users.findByUsername(name)).isPresent();

        Map<String, Object> signup = example(api, "/auth/register", "post");
        String unique = "f1." + UUID.randomUUID().toString().substring(0, 8);
        String email = unique + "@example.test";
        signup.putAll(Map.of("username", unique, "email", email, "password", PASSWORD));
        signup.put("firstName", null);
        signup.put("lastName", null);
        signup.put("deviceType", null);
        requestOtp(api, email, "SIGNUP");
        signup.put("otpCode", SMTP.code(email));
        var registered = call("POST", "/api/v1/auth/register", null, null, signup);
        assertThat(registered.statusCode()).isEqualTo(201);
        JsonNode tokens = body(registered).path("data");
        String customer = tokens.path("accessToken").asText();
        assertThat(call("GET", "/api/v1/auth/me", customer, null, null).statusCode()).isEqualTo(200);
        assertThat(body(call("GET", "/api/v1/accounts/me", customer, null, null)).path("data").size()).isZero();

        var opened = call("POST", "/api/v1/accounts", customer, null, example(api, "/accounts", "post"));
        assertThat(opened.statusCode()).isEqualTo(201);
        String number = body(opened).path("data").path("accountNumber").asText();
        assertThat(body(opened).path("data").path("balance").decimalValue()).isZero();
        String staff = login(api, "employee.demo");
        Map<String, Object> deposit = example(api, "/transactions/deposit", "post");
        deposit.put("accountNumber", number);
        deposit.put("remark", null);
        assertThat(call("POST", "/api/v1/transactions/deposit", customer, unique, deposit).statusCode()).isEqualTo(403);
        assertThat(call("POST", "/api/v1/transactions/deposit", staff, unique, deposit).statusCode()).isEqualTo(200);
        Map<String, Object> status = example(api, "/accounts/{accountNumber}/status", "patch");
        assertThat(call("PATCH", "/api/v1/accounts/" + number + "/status", customer, null, status).statusCode()).isEqualTo(403);
        assertThat(call("PATCH", "/api/v1/accounts/" + number + "/status", staff, null, status).statusCode()).isEqualTo(200);
        status.put("status", "ACTIVE");
        assertThat(call("PATCH", "/api/v1/accounts/" + number + "/status", staff, null, status).statusCode()).isEqualTo(200);

        String bob = login(api, "bob.demo");
        assertThat(call("GET", "/api/v1/accounts/" + number, bob, null, null).statusCode()).isEqualTo(404);
        assertThat(call("GET", "/api/v1/transactions/account/" + number, bob, null, null).statusCode()).isEqualTo(404);
        Map<String, Object> transfer = example(api, "/transactions/transfer", "post");
        transfer.put("sourceAccountNumber", number);
        transfer.put("remark", null);
        String transferKey = unique + ".transfer";
        var sent = call("POST", "/api/v1/transactions/transfer", customer, transferKey, transfer);
        assertThat(sent.statusCode()).isEqualTo(200);
        String reference = body(sent).path("data").path("referenceNumber").asText();
        assertThat(body(call("POST", "/api/v1/transactions/transfer", customer, transferKey, transfer))
                .path("data").path("referenceNumber").asText()).isEqualTo(reference);
        assertThat(body(call("GET", "/api/v1/accounts/" + number, customer, null, null))
                .path("data").path("balance").decimalValue()).isEqualByComparingTo("75.00");
        assertThat(body(call("GET", "/api/v1/transactions/account/" + number, customer, null, null))
                .path("data").path("content").size()).isEqualTo(2);
        assertThat(call("GET", "/api/v1/transactions/" + reference, customer, null, null).statusCode()).isEqualTo(200);

        Map<String, Object> refresh = example(api, "/auth/refresh", "post");
        refresh.put("refreshToken", tokens.path("refreshToken").asText());
        var renewed = call("POST", "/api/v1/auth/refresh", null, null, refresh);
        assertThat(renewed.statusCode()).isEqualTo(200);
        JsonNode replacements = body(renewed).path("data");
        String renewedAccess = replacements.path("accessToken").asText();
        assertThat(call("POST", "/api/v1/auth/logout", renewedAccess, null, null).statusCode()).isEqualTo(200);
        assertThat(call("GET", "/api/v1/auth/me", renewedAccess, null, null).statusCode()).isEqualTo(401);
        assertThat(call("POST", "/api/v1/auth/refresh", null, null,
                Map.of("refreshToken", replacements.path("refreshToken").asText())).statusCode()).isEqualTo(401);
        assertThat(call("POST", "/api/v1/auth/logout", staff, null, null).statusCode()).isEqualTo(200);
        assertThat(call("POST", "/api/v1/auth/logout", bob, null, null).statusCode()).isEqualTo(200);
    }

    String login(JsonNode api, String username) throws Exception {
        String email = username + "@example.test";
        requestOtp(api, email, "LOGIN");
        Map<String, Object> login = example(api, "/auth/login", "post");
        login.putAll(Map.of("usernameOrEmail", email, "password", PASSWORD,
                "otpCode", SMTP.code(email), "deviceFingerprint", "f1-" + UUID.randomUUID()));
        var response = call("POST", "/api/v1/auth/login", null, null, login);
        assertThat(response.statusCode()).isEqualTo(200);
        return body(response).path("data").path("accessToken").asText();
    }

    void requestOtp(JsonNode api, String email, String purpose) throws Exception {
        Map<String, Object> request = example(api, "/auth/request-otp", "post");
        request.putAll(Map.of("email", email, "purpose", purpose));
        var response = call("POST", "/api/v1/auth/request-otp", null, null, request);
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).doesNotContain(SMTP.code(email));
    }

    JsonNode operation(JsonNode api, String path, String method) {
        return api.path("paths").path("/api/v1" + path).path(method);
    }

    @SuppressWarnings("unchecked")
    Map<String, Object> example(JsonNode api, String path, String method) {
        return new LinkedHashMap<>(json.convertValue(operation(api, path, method).path("requestBody")
                .path("content").path("application/json").path("example"), Map.class));
    }

    HttpResponse<String> call(String method, String path, String token, String key, Object payload) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path)).timeout(Duration.ofSeconds(20));
        if (token != null) request.header("Authorization", "Bearer " + token);
        if (key != null) request.header("Idempotency-Key", key);
        if (payload != null) request.header("Content-Type", "application/json");
        return client.send(request.method(method, payload == null ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload))).build(), HttpResponse.BodyHandlers.ofString());
    }

    JsonNode body(HttpResponse<String> response) { return json.readTree(response.body()); }
}
