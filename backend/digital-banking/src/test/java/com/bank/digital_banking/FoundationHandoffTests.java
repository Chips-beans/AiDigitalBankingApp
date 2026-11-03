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

    @Test void nativeMigrationPreservesExistingV10ProfilesAndBrowserFlows() throws Exception {
        try (var postgres = EmbeddedPostgres.builder().setPort(0).start()) {
            String url = postgres.getJdbcUrl("postgres", "postgres");
            Flyway.configure().dataSource(url, "postgres", "postgres").target("10").load().migrate();
            try (var connection = java.sql.DriverManager.getConnection(url); var statement = connection.createStatement()) {
                statement.executeUpdate("INSERT INTO users(username,email) VALUES ('native.upgrade','upgrade@example.test')");
                statement.executeUpdate("INSERT INTO telegram_login_flows(id,exchange_secret_hash,verifier,nonce,expires_at,device_fingerprint,device_name) "
                        + "VALUES ('upgrade-flow','saved-hash','saved-verifier','saved-nonce',CURRENT_TIMESTAMP + INTERVAL '5 minutes','saved-device','Existing browser')");
            }
            var upgraded = Flyway.configure().dataSource(url, "postgres", "postgres").load();
            upgraded.migrate(); upgraded.validate();
            assertThat(upgraded.info().current().getVersion().getVersion()).isEqualTo("21");
            try (var connection = java.sql.DriverManager.getConnection(url); var statement = connection.createStatement()) {
                try (var row = statement.executeQuery("SELECT profile_complete FROM users WHERE username='native.upgrade'")) {
                    assertThat(row.next()).isTrue(); assertThat(row.getBoolean(1)).isTrue();
                }
                try (var row = statement.executeQuery("SELECT native_flow,redirect_uri,verifier,nonce FROM telegram_login_flows WHERE id='upgrade-flow'")) {
                    assertThat(row.next()).isTrue(); assertThat(row.getBoolean(1)).isFalse(); assertThat(row.getString(2)).isNull();
                    assertThat(row.getString(3)).isEqualTo("saved-verifier"); assertThat(row.getString(4)).isEqualTo("saved-nonce");
                }
            }
        }
    }

    @Test void freshInstallAndRestartPreserveMoneyReplaySessionsAndLogout() throws Exception {
        try (var postgres = EmbeddedPostgres.builder().setPort(0).start();
             var smtp = new LocalSmtpServer()) {
            String url = postgres.getJdbcUrl("postgres", "postgres");
            JsonNode sender;
            JsonNode receiver;
            String source;
            String destination;
            JsonNode receipt;
            JsonNode openedPair;
            JsonNode qrReceipt;
            Map<String, Object> qrTransfer;
            com.bank.digital_banking.module.auth.service.ProfilePhotoService.Photo savedPhoto;
            String durablePinTicket;
            Map<String, Object> transfer;
            String assistantConversation;
            JsonNode assistantResult;
            Map<String,Object> merchantExchange;
            JsonNode merchantTokens;

            try (var app = start(url, smtp.port())) {
                use(app);
                var flyway = app.getBean(Flyway.class);
                flyway.validate();
                assertThat(flyway.info().applied()).hasSize(20);
                assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("21");
                assertThat(flyway.info().pending()).isEmpty();

                sender = signup("handoff.sender", smtp);
                receiver = signup("handoff.receiver", smtp);
                JsonNode pinCustomer = signup("handoff.pin", smtp);
                durablePinTicket = ok("POST", "/auth/pin/prepare", pinCustomer.path("accessToken").asText(), null, null, 200).path("ticket").asText();
                ok("POST", "/auth/pin/setup", null, null, Map.of("ticket", durablePinTicket, "pin", "0427", "confirmPin", "0427"), 200);
                assertThat(call("POST", "/auth/pin/unlock", null, null, Map.of("ticket", durablePinTicket, "pin", "9999")).statusCode()).isEqualTo(403);
                String senderAccess = sender.path("accessToken").asText();
                String receiverAccess = receiver.path("accessToken").asText();
                assistantConversation=ok("POST","/ai/conversations",senderAccess,"handoff-ai-create",null,201).path("id").asText();
                assertThat(call("POST","/ai/conversations/"+assistantConversation+"/messages",senderAccess,"handoff-ai-message",Map.of("message","balances","locale","en")).statusCode()).isEqualTo(503);
                assistantResult=ok("GET","/ai/conversations/"+assistantConversation+"/requests/handoff-ai-message",senderAccess,null,null,200);
                assertThat(assistantResult.path("status").asText()).isEqualTo("FAILED");
                var photoImage = new java.awt.image.BufferedImage(2, 2, java.awt.image.BufferedImage.TYPE_INT_RGB);
                var photoBytes = new java.io.ByteArrayOutputStream();
                javax.imageio.ImageIO.write(photoImage, "png", photoBytes);
                savedPhoto = app.getBean(com.bank.digital_banking.module.auth.service.ProfilePhotoService.class).save(
                        app.getBean(com.bank.digital_banking.module.auth.repository.UserRepository.class)
                                .findByUsername("handoff.sender").orElseThrow(),
                        new org.springframework.mock.web.MockMultipartFile("photo", "photo.png", "image/png", photoBytes.toByteArray()));
                assertThat(ok("GET", "/accounts/me", senderAccess, null, null, 200).size()).isEqualTo(2);
                assertThat(ok("GET", "/accounts/me", receiverAccess, null, null, 200).size()).isEqualTo(2);
                source = ok("GET", "/accounts/me", senderAccess, null, null, 200).get(0).path("accountNumber").asText();
                destination = ok("GET", "/accounts/me", receiverAccess, null, null, 200).get(0).path("accountNumber").asText();

                ok("POST", "/auth/request-otp", null, null,
                        Map.of("email", "employee.demo@example.test", "purpose", "LOGIN"), 200);
                JsonNode staff = ok("POST", "/auth/login", null, null, Map.of(
                        "usernameOrEmail", "employee.demo@example.test", "password", PASSWORD,
                        "otpCode", smtp.code("employee.demo@example.test"),
                        "deviceFingerprint", "handoff.staff", "deviceName", "Handoff test"), 200);
                String staffAccess = staff.path("accessToken").asText();
                assertThat(call("GET", "/auth/profile/photo", staffAccess, null, null).statusCode()).isEqualTo(401);
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
                openedPair = ok("POST", "/accounts/pairs", senderAccess, "handoff.pair", Map.of("accountType", "SAVINGS"), 201);
                String qr = ok("POST", "/payments/qr/generate", receiverAccess, null,
                        Map.of("accountNumber", destination, "currency", "USD", "amount", "1.00"), 200).path("qrString").asText();
                qrTransfer = Map.of("sourceAccountNumber", source, "qrString", qr, "amount", "1.00", "currency", "USD");
                qrReceipt = ok("POST", "/payments/qr/transfer", senderAccess, "handoff.qr", qrTransfer, 200);
                assertThat(call("GET", "/accounts/" + source, receiverAccess, null, null).statusCode()).isEqualTo(404);
                assertThat(call("GET", "/transactions/account/" + source, receiverAccess, null, null).statusCode())
                        .isEqualTo(404);
                // Exercise encrypted response-loss recovery across a real server
                // restart, using the synthetic customer's existing PIN.
                String merchantOwnerAccess=ok("POST", "/auth/pin/unlock", null, null,
                        Map.of("ticket",durablePinTicket,"pin","0427"),200).path("accessToken").asText();
                String verifier=randomCredential(),secret=randomCredential(),state=randomCredential();
                String challenge=java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                        java.util.HexFormat.of().parseHex(com.bank.digital_banking.common.util.HashUtils.sha256(verifier)));
                JsonNode attempt=ok("POST","/merchant-auth/attempts",null,null,Map.of(
                        "clientId","kesor-merchant-android","redirectUri","kesormerchant://auth/callback",
                        "state",state,"codeChallenge",challenge,"codeChallengeMethod","S256",
                        "attemptSecretHash",com.bank.digital_banking.common.util.HashUtils.sha256(secret),
                        "installationId",randomCredential(),"deviceName","Restart fixture"),200);
                String handoff=queryParameter(attempt.path("approvalUri").asText(),"handoffToken");
                String callback=ok("POST","/merchant-auth/attempts/"+attempt.path("attemptId").asText()+"/approve",
                        merchantOwnerAccess,null,Map.of("handoffToken",handoff,"pin","0427"),200).path("callbackUri").asText();
                merchantExchange=Map.of("attemptId",attempt.path("attemptId").asText(),"code",queryParameter(callback,"code"),
                        "codeVerifier",verifier,"attemptSecret",secret,"exchangeKey",randomCredential(),"state",state,
                        "clientId","kesor-merchant-android","redirectUri","kesormerchant://auth/callback");
                merchantTokens=ok("POST","/merchant-auth/exchange",null,null,merchantExchange,200);
                // Keep the original failure-persistence assertion in the restart test.
                assertThat(call("POST","/auth/pin/unlock",null,null,Map.of("ticket",durablePinTicket,"pin","9999")).statusCode()).isEqualTo(403);
            }

            JsonNode renewed;
            try (var app = start(url, smtp.port())) {
                use(app);
                var flyway = app.getBean(Flyway.class);
                flyway.validate();
                assertThat(flyway.info().applied()).hasSize(20);
                assertThat(flyway.info().pending()).isEmpty();
                assertThat(ok("POST","/merchant-auth/exchange",null,null,merchantExchange,200)).isEqualTo(merchantTokens);
                assertThat(ok("GET","/merchant-auth/session",merchantTokens.path("accessToken").asText(),null,null,200)
                        .path("onboardingState").asText()).isEqualTo("SHOP_REQUIRED");
                JsonNode pinState = ok("POST", "/auth/pin/status", null, null, Map.of("ticket", durablePinTicket), 200);
                assertThat(pinState.path("configured").asBoolean()).isTrue();
                assertThat(pinState.path("attemptsRemaining").asInt()).isEqualTo(4);
                assertThat(pinState.path("canRecover").asBoolean()).isFalse();
                JsonNode pinUnlocked = ok("POST", "/auth/pin/unlock", null, null, Map.of("ticket", durablePinTicket, "pin", "0427"), 200);
                assertThat(ok("GET", "/accounts/me", pinUnlocked.path("accessToken").asText(), null, null, 200).size()).isEqualTo(2);
                renewed = ok("POST", "/auth/refresh", null, null,
                        Map.of("refreshToken", sender.path("refreshToken").asText()), 200);
                assertThat(renewed.path("sessionId").asText()).isEqualTo(sender.path("sessionId").asText());
                assertThat(renewed.path("refreshToken").asText()).isNotEqualTo(sender.path("refreshToken").asText());
                String senderAccess = renewed.path("accessToken").asText();
                assertThat(ok("POST","/ai/conversations",senderAccess,"handoff-ai-create",null,201).path("id").asText()).isEqualTo(assistantConversation);
                assertThat(ok("GET","/ai/conversations/"+assistantConversation+"/requests/handoff-ai-message",senderAccess,null,null,200)).isEqualTo(assistantResult);
                assertThat(ok("GET", "/auth/profile/photo", senderAccess, null, null, 200)
                        .path("imageBase64").asText()).isEqualTo(savedPhoto.imageBase64());
                String receiverAccess = receiver.path("accessToken").asText();
                assertThat(ok("GET", "/auth/me", senderAccess, null, null, 200).path("userId"))
                        .isEqualTo(sender.path("userId"));
                assertThat(ok("POST", "/transactions/transfer", senderAccess, "handoff.transfer", transfer, 200))
                        .isEqualTo(receipt);
                assertThat(ok("POST", "/accounts/pairs", senderAccess, "handoff.pair", Map.of("accountType", "SAVINGS"), 201)).isEqualTo(openedPair);
                assertThat(ok("POST", "/payments/qr/transfer", senderAccess, "handoff.qr", qrTransfer, 200)).isEqualTo(qrReceipt);
                balance(source, senderAccess, "74.00");
                balance(destination, receiverAccess, "26.00");
                String reference = receipt.path("referenceNumber").asText();
                history(source, senderAccess, reference, 3);
                history(destination, receiverAccess, reference, 2);
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
                "--app.ai.gemini.enabled=false", "--app.ai.gemini.customer-context-enabled=false",
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
                // Restart/replay is the subject here; PIN proofs (and proof-free replays) are covered by TransferPinAndExchangeTests.
                "--app.transfer.pin-proof-required=false",
                "--app.ai.enabled=false", "--spring.main.banner-mode=off", "--logging.level.root=WARN");
    }
    private String randomCredential() {
        byte[] bytes=new byte[32]; new java.security.SecureRandom().nextBytes(bytes);
        return java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
    private String queryParameter(String uri,String key) {
        return java.util.Arrays.stream(URI.create(uri).getRawQuery().split("&")).map(p->p.split("=",2))
                .filter(p->p[0].equals(key)).findFirst().orElseThrow()[1];
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
