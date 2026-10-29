package com.bank.digital_banking;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.ConfigurableApplicationContext;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/** Fresh database and actual server-context restarts; never connects to the development database. */
class FoundationHandoffTests {
    private static final String PASSWORD = "HandoffTestOnly!2026";
    private final ObjectMapper json = new ObjectMapper();
    private final HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private int port;

    @Test void freshInstallAndRestartPreserveMoneyReplaySessionsAndLogout() throws Exception {
        try (var postgres = EmbeddedPostgres.builder().setPort(0).start();
             var smtp = new LocalSmtpServer()) {
            String url = postgres.getJdbcUrl("postgres", "postgres");
            JsonNode sender;
            JsonNode receiver;
            String source;
            String destination;
            JsonNode receipt;
            Map<String, Object> transfer;

            try (var app = start(url, smtp.port())) {
                use(app);
                var flyway = app.getBean(Flyway.class);
                flyway.validate();
                assertThat(flyway.info().applied()).hasSize(9);
                assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("10");
                assertThat(flyway.info().pending()).isEmpty();

                sender = signup("handoff.sender", smtp);
                receiver = signup("handoff.receiver", smtp);
                String senderAccess = sender.path("accessToken").asText();
                String receiverAccess = receiver.path("accessToken").asText();
                assertThat(ok("GET", "/accounts/me", senderAccess, null, null, 200).size()).isZero();
                assertThat(ok("GET", "/accounts/me", receiverAccess, null, null, 200).size()).isZero();
                source = open(senderAccess);
                destination = open(receiverAccess);

                ok("POST", "/auth/request-otp", null, null,
                        Map.of("email", "employee.demo@example.test", "purpose", "LOGIN"), 200);
                JsonNode staff = ok("POST", "/auth/login", null, null, Map.of(
                        "usernameOrEmail", "employee.demo@example.test", "password", PASSWORD,
                        "otpCode", smtp.code("employee.demo@example.test"),
                        "deviceFingerprint", "handoff.staff", "deviceName", "Handoff test"), 200);
                String staffAccess = staff.path("accessToken").asText();
                Map<String, Object> deposit = Map.of("accountNumber", source, "amount", 100,
                        "currency", "USD", "remark", "Isolated test funds");
                assertThat(call("POST", "/transactions/deposit", senderAccess, "forbidden", deposit).statusCode())
                        .isEqualTo(403);
                ok("POST", "/transactions/deposit", staffAccess, "handoff.deposit", deposit, 200);
                ok("POST", "/auth/logout", staffAccess, null, null, 200);

                transfer = Map.of("sourceAccountNumber", source, "destinationAccountNumber", destination,
                        "amount", 25, "currency", "USD", "remark", "Restart replay");
                // Treat this response as lost by the customer, then reuse the key after server restart.
                receipt = ok("POST", "/transactions/transfer", senderAccess, "handoff.transfer", transfer, 200);
                balance(source, senderAccess, "75.00");
                balance(destination, receiverAccess, "25.00");
                assertThat(call("GET", "/accounts/" + source, receiverAccess, null, null).statusCode()).isEqualTo(404);
                assertThat(call("GET", "/transactions/account/" + source, receiverAccess, null, null).statusCode())
                        .isEqualTo(404);
            }

            JsonNode renewed;
            try (var app = start(url, smtp.port())) {
                use(app);
                var flyway = app.getBean(Flyway.class);
                flyway.validate();
                assertThat(flyway.info().applied()).hasSize(9);
                assertThat(flyway.info().pending()).isEmpty();
                renewed = ok("POST", "/auth/refresh", null, null,
                        Map.of("refreshToken", sender.path("refreshToken").asText()), 200);
                assertThat(renewed.path("sessionId").asText()).isEqualTo(sender.path("sessionId").asText());
                assertThat(renewed.path("refreshToken").asText()).isNotEqualTo(sender.path("refreshToken").asText());
                String senderAccess = renewed.path("accessToken").asText();
                String receiverAccess = receiver.path("accessToken").asText();
                assertThat(ok("GET", "/auth/me", senderAccess, null, null, 200).path("userId"))
                        .isEqualTo(sender.path("userId"));
                assertThat(ok("POST", "/transactions/transfer", senderAccess, "handoff.transfer", transfer, 200))
                        .isEqualTo(receipt);
                balance(source, senderAccess, "75.00");
                balance(destination, receiverAccess, "25.00");
                String reference = receipt.path("referenceNumber").asText();
                history(source, senderAccess, reference, 2);
                history(destination, receiverAccess, reference, 1);
                detail(senderAccess, receipt);
                detail(receiverAccess, receipt);
                ok("POST", "/auth/logout", senderAccess, null, null, 200);
                ok("POST", "/auth/logout", receiverAccess, null, null, 200);
            }

            try (var app = start(url, smtp.port())) {
                use(app);
                for (JsonNode tokens : new JsonNode[]{renewed, receiver}) {
                    assertThat(call("GET", "/auth/me", tokens.path("accessToken").asText(), null, null).statusCode())
                            .isEqualTo(401);
                    assertThat(call("POST", "/auth/refresh", null, null,
                            Map.of("refreshToken", tokens.path("refreshToken").asText())).statusCode()).isEqualTo(401);
                }
                // Reconnect through JDBC after all application restarts to check durable financial rows.
                try (var connection = postgres.getPostgresDatabase().getConnection();
                     var query = connection.prepareStatement("select count(*) from transactions where reference_number=?")) {
                    query.setString(1, receipt.path("referenceNumber").asText());
                    try (var rows = query.executeQuery()) {
                        assertThat(rows.next()).isTrue();
                        assertThat(rows.getInt(1)).isEqualTo(1);
                    }
                }
            }
        }
    }

    private ConfigurableApplicationContext start(String url, int smtpPort) {
        return new SpringApplicationBuilder(DigitalBankingApplication.class).run(
                "--spring.profiles.active=local,test", "--server.port=0",
                "--spring.datasource.url=" + url, "--spring.datasource.username=postgres",
                "--spring.datasource.password=postgres", "--spring.datasource.hikari.maximum-pool-size=2",
                "--spring.datasource.hikari.minimum-idle=0",
                "--app.jwt.secret=MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=",
                "--app.dev.seed.enabled=true", "--app.dev.seed.password=" + PASSWORD,
                "--app.dev.qa-staff.enabled=false", "--spring.mail.host=localhost",
                "--spring.mail.port=" + smtpPort, "--spring.mail.username=wallet@example.test",
                "--spring.mail.password=", "--spring.mail.properties.mail.smtp.from=wallet@example.test",
                "--spring.mail.properties.mail.from=wallet@example.test",
                "--spring.mail.properties.mail.smtp.auth=false",
                "--spring.mail.properties.mail.smtp.starttls.enable=false",
                "--spring.mail.properties.mail.smtp.starttls.required=false",
                "--app.ai.enabled=false", "--spring.main.banner-mode=off", "--logging.level.root=WARN");
    }

    private void use(ConfigurableApplicationContext app) {
        port = ((WebServerApplicationContext) app).getWebServer().getPort();
    }

    private JsonNode signup(String username, LocalSmtpServer smtp) throws Exception {
        String email = username + "@example.test";
        ok("POST", "/auth/request-otp", null, null, Map.of("email", email, "purpose", "SIGNUP"), 200);
        return ok("POST", "/auth/register", null, null, Map.of("username", username, "email", email,
                "password", PASSWORD, "otpCode", smtp.code(email), "deviceFingerprint", username,
                "deviceName", "Handoff test"), 201);
    }

    private String open(String token) throws Exception {
        JsonNode account = ok("POST", "/accounts", token, null,
                Map.of("accountType", "SAVINGS", "currency", "USD", "initialDeposit", 0), 201);
        assertThat(account.path("balance").decimalValue()).isZero();
        return account.path("accountNumber").asText();
    }

    private void balance(String number, String token, String expected) throws Exception {
        assertThat(ok("GET", "/accounts/" + number, token, null, null, 200).path("balance").decimalValue())
                .isEqualByComparingTo(expected);
    }

    private void history(String number, String token, String reference, int count) throws Exception {
        JsonNode history = ok("GET", "/transactions/account/" + number + "?page=0&size=20", token, null, null, 200);
        assertThat(history.path("totalElements").asInt()).isEqualTo(count);
        int matches = 0;
        for (JsonNode transaction : history.path("content"))
            if (transaction.path("referenceNumber").asText().equals(reference)) matches++;
        assertThat(matches).isEqualTo(1);
    }

    private void detail(String token, JsonNode receipt) throws Exception {
        JsonNode detail = ok("GET", "/transactions/" + receipt.path("referenceNumber").asText(), token, null, null, 200);
        for (String field : new String[]{"id", "referenceNumber", "sourceAccountNumber", "destinationAccountNumber",
                "currency", "transactionType", "status", "remark"})
            assertThat(detail.path(field)).as(field).isEqualTo(receipt.path(field));
        for (String field : new String[]{"amount", "fee"})
            assertThat(detail.path(field).decimalValue()).as(field).isEqualByComparingTo(receipt.path(field).decimalValue());
        // PostgreSQL persists microseconds; the original receipt can contain JVM nanoseconds.
        assertThat(Duration.between(java.time.Instant.parse(receipt.path("createdAt").asText()),
                java.time.Instant.parse(detail.path("createdAt").asText())).abs()).isLessThanOrEqualTo(Duration.ofNanos(1000));
    }

    private JsonNode ok(String method, String path, String token, String key, Object payload, int status) throws Exception {
        var response = call(method, path, token, key, payload);
        // Do not include auth response bodies: they contain tokens.
        assertThat(response.statusCode()).as(method + " " + path).isEqualTo(status);
        JsonNode envelope = json.readTree(response.body());
        assertThat(envelope.path("success").asBoolean()).isTrue();
        return envelope.path("data");
    }

    private HttpResponse<String> call(String method, String path, String token, String key, Object payload) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1" + path))
                .timeout(Duration.ofSeconds(20));
        if (token != null) request.header("Authorization", "Bearer " + token);
        if (key != null) request.header("Idempotency-Key", key);
        if (payload != null) request.header("Content-Type", "application/json");
        return client.send(request.method(method, payload == null ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload))).build(), HttpResponse.BodyHandlers.ofString());
    }
}
