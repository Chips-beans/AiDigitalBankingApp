package com.bank.digital_banking;

import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.payment.repository.PaymentRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import java.math.BigDecimal;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@org.springframework.test.context.TestPropertySource(properties = "app.dev.opening-funding.enabled=false")
class QrPaymentIntegrationTests extends PostgresIntegrationTest {

    @Value("${local.server.port}")
    int port;

    @Autowired
    ObjectMapper json;

    @Autowired
    UserRepository users;

    @Autowired
    AccountRepository accounts;

    @Autowired
    PaymentRepository payments;

    @Autowired
    com.bank.digital_banking.module.auth.repository.OtpRateLimitRepository limits;

    @Autowired
    com.bank.digital_banking.module.auth.repository.AuthSessionRepository sessions;
    @Autowired org.springframework.jdbc.core.JdbcTemplate jdbc;

    final HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    @BeforeEach
    void reset() {
        loginLimits.deleteAll();
        jdbc.update("DELETE FROM merchant_auth_attempts");
        sessions.deleteAll();
        limits.deleteAll();
        SMTP.reset();
    }

    @Autowired com.bank.digital_banking.module.auth.repository.LoginAttemptLimitRepository loginLimits;

    @Test
    void aliceGeneratesDynamicQr_bobScansAndTransfersSuccessfully() throws Exception {
        // 1. Alice logs in
        String aliceToken = login("alice.demo", "device-alice").path("accessToken").asText();

        // Initial balances: Alice has account 9000000001 ($1000.00), Bob has account 9000000002 ($500.00)
        BigDecimal aliceInitial = accounts.findByAccountNumber("9000000001").orElseThrow().getBalance();
        BigDecimal bobInitial = accounts.findByAccountNumber("9000000002").orElseThrow().getBalance();

        // 2. Alice generates dynamic QR code for $50.00 USD
        var genResponse = call("POST", "/payments/qr/generate", aliceToken, Map.of(
                "accountNumber", "9000000001",
                "amount", 50.00,
                "currency", "USD",
                "remark", "Lunch with Bob",
                "billNumber", "BILL-889"
        ));
        assertThat(genResponse.statusCode()).as(genResponse.body()).isEqualTo(200);

        JsonNode genData = body(genResponse).path("data");
        String qrString = genData.path("qrString").asText();
        String qrHash = genData.path("qrHash").asText();
        assertThat(qrString).startsWith("000201010212"); // EMVCo dynamic point of initiation
        assertThat(genData.path("accountNumber").asText()).isEqualTo("9000000001");
        assertThat(genData.path("amount").asDouble()).isEqualTo(50.00);
        assertThat(genData.path("currency").asText()).isEqualTo("USD");
        assertThat(genData.path("qrType").asText()).isEqualTo("DYNAMIC");
        assertThat(genData.path("payloadComponents")).isNotNull();

        // Verify status initially PENDING
        var initVerify = call("GET", "/payments/verify/" + qrHash, aliceToken, null);
        assertThat(initVerify.statusCode()).isEqualTo(200);
        assertThat(body(initVerify).path("isPaid").asBoolean()).isFalse();

        // 3. Bob logs in and scans Alice's QR code
        String bobToken = login("bob.demo", "device-bob").path("accessToken").asText();
        var scanResponse = call("POST", "/payments/qr/scan", bobToken, Map.of("qrString", qrString));
        assertThat(scanResponse.statusCode()).as(scanResponse.body()).isEqualTo(200);

        JsonNode scanData = body(scanResponse).path("data");
        assertThat(scanData.path("valid").asBoolean()).isTrue();
        assertThat(scanData.path("destinationAccountNumber").asText()).isEqualTo("9000000001");
        assertThat(scanData.path("amount").asDouble()).isEqualTo(50.00);
        assertThat(scanData.path("currency").asText()).isEqualTo("USD");
        assertThat(scanData.path("isDynamic").asBoolean()).isTrue();
        assertThat(scanData.path("remark").asText()).isEqualTo("Lunch with Bob");
        assertThat(scanData.path("isAlreadyPaid").asBoolean()).isFalse();

        // 4. Bob executes transfer payment by QR
        var transferResponse = call("POST", "/payments/qr/transfer", bobToken, Map.of(
                "sourceAccountNumber", "9000000002",
                "qrString", qrString,
                "amount", 50.00,
                "currency", "USD"
        ));
        assertThat(transferResponse.statusCode()).as(transferResponse.body()).isEqualTo(200);

        JsonNode transferData = body(transferResponse).path("data");
        assertThat(transferData.path("status").asText()).isEqualTo("COMPLETED");
        assertThat(transferData.path("referenceNumber").asText()).isNotBlank();
        assertThat(transferData.path("amount").asDouble()).isEqualTo(50.00);

        // 5. Verify balances: Alice +50, Bob -50
        BigDecimal aliceAfter = accounts.findByAccountNumber("9000000001").orElseThrow().getBalance();
        BigDecimal bobAfter = accounts.findByAccountNumber("9000000002").orElseThrow().getBalance();
        assertThat(aliceAfter).isEqualByComparingTo(aliceInitial.add(new BigDecimal("50.00")));
        assertThat(bobAfter).isEqualByComparingTo(bobInitial.subtract(new BigDecimal("50.00")));

        // 6. Alice verifies payment status -> SUCCESS and isPaid = true
        var finalVerify = call("GET", "/payments/verify/" + qrHash, aliceToken, null);
        assertThat(finalVerify.statusCode()).isEqualTo(200);
        assertThat(body(finalVerify).path("isPaid").asBoolean()).isTrue();
        assertThat(body(finalVerify).path("status").asText()).isEqualTo("SUCCESS");

        // 7. Scanning or paying again reports already paid
        var reScan = call("POST", "/payments/qr/scan", bobToken, Map.of("qrString", qrString));
        assertThat(reScan.statusCode()).isEqualTo(200);
        assertThat(body(reScan).path("data").path("isAlreadyPaid").asBoolean()).isTrue();

        var reTransfer = call("POST", "/payments/qr/transfer", bobToken, Map.of(
                "sourceAccountNumber", "9000000002",
                "qrString", qrString,
                "amount", 50.00,
                "currency", "USD"
        ));
        assertThat(reTransfer.statusCode()).isEqualTo(409); // Conflict: already completed
    }

    @Test
    void staticQrTransferAllowsPayerToSpecifyAmount() throws Exception {
        String aliceToken = login("alice.demo", "device-alice-static").path("accessToken").asText();
        String bobToken = login("bob.demo", "device-bob-static").path("accessToken").asText();

        BigDecimal aliceInitial = accounts.findByAccountNumber("9000000001").orElseThrow().getBalance();
        BigDecimal bobInitial = accounts.findByAccountNumber("9000000002").orElseThrow().getBalance();

        // Alice generates static QR (no fixed amount)
        var gen = call("POST", "/payments/qr/generate", aliceToken, Map.of(
                "accountNumber", "9000000001",
                "currency", "USD",
                "qrType", "STATIC",
                "remark", "Tip jar"
        ));
        assertThat(gen.statusCode()).isEqualTo(200);
        String qrString = body(gen).path("data").path("qrString").asText();
        assertThat(qrString).startsWith("000201010211"); // EMVCo static point of initiation

        // Bob scans static QR
        var scan = call("POST", "/payments/qr/scan", bobToken, Map.of("qrString", qrString));
        assertThat(scan.statusCode()).isEqualTo(200);
        assertThat(body(scan).path("data").path("isDynamic").asBoolean()).isFalse();

        // Bob specifies $15.00 transfer
        var transfer = call("POST", "/payments/qr/transfer", bobToken, Map.of(
                "sourceAccountNumber", "9000000002",
                "qrString", qrString,
                "amount", 15.00,
                "currency", "USD",
                "remark", "Great coffee"
        ));
        assertThat(transfer.statusCode()).isEqualTo(200);

        BigDecimal aliceAfter = accounts.findByAccountNumber("9000000001").orElseThrow().getBalance();
        BigDecimal bobAfter = accounts.findByAccountNumber("9000000002").orElseThrow().getBalance();
        assertThat(aliceAfter).isEqualByComparingTo(aliceInitial.add(new BigDecimal("15.00")));
        assertThat(bobAfter).isEqualByComparingTo(bobInitial.subtract(new BigDecimal("15.00")));
    }

    @Test
    void cannotTransferToSelfViaQr() throws Exception {
        String aliceToken = login("alice.demo", "device-alice-self").path("accessToken").asText();

        var gen = call("POST", "/payments/qr/generate", aliceToken, Map.of(
                "accountNumber", "9000000001",
                "amount", 10.00,
                "currency", "USD"
        ));
        String qrString = body(gen).path("data").path("qrString").asText();

        var transfer = call("POST", "/payments/qr/transfer", aliceToken, Map.of(
                "sourceAccountNumber", "9000000001",
                "qrString", qrString,
                "amount", 10.00,
                "currency", "USD"
        ));
        assertThat(transfer.statusCode()).isEqualTo(400);
    }

    @Test
    void cannotTransferMoreThanAccountBalance() throws Exception {
        String aliceToken = login("alice.demo", "device-alice-high").path("accessToken").asText();
        String bobToken = login("bob.demo", "device-bob-high").path("accessToken").asText();

        var gen = call("POST", "/payments/qr/generate", aliceToken, Map.of(
                "accountNumber", "9000000001",
                "amount", 9999999.00,
                "currency", "USD"
        ));
        String qrString = body(gen).path("data").path("qrString").asText();

        var transfer = call("POST", "/payments/qr/transfer", bobToken, Map.of(
                "sourceAccountNumber", "9000000002",
                "qrString", qrString,
                "amount", 9999999.00,
                "currency", "USD"
        ));
        assertThat(transfer.statusCode()).isEqualTo(400);
    }

    @Test
    void legacyKhqrGenerateAndMerchantQrConfigWork() throws Exception {
        String aliceToken = login("alice.demo", "device-alice-legacy").path("accessToken").asText();

        var response = call("POST", "/payments/khqr/generate", aliceToken, Map.of(
                "accountNumber", "9000000001",
                "amount", 20.00,
                "currency", "USD"
        ));
        assertThat(response.statusCode()).isEqualTo(200);
        JsonNode data = body(response);
        assertThat(data.path("qrString").asText()).isNotBlank();
        assertThat(data.path("md5Hash").asText()).isNotBlank();
        assertThat(data.path("accountNumber").asText()).isEqualTo("9000000001");
        assertThat(data.path("amount").asDouble()).isEqualTo(20.00);
    }

    // --- Helper Methods ---

    @Test void pairedOpeningIsZeroFundedByDefault() throws Exception {
        // A customer without wallets, so the pair is actually opened rather than returning seeded accounts.
        var template = users.findByUsername("alice.demo").orElseThrow();
        String name = "pair.default." + UUID.randomUUID().toString().substring(0, 8);
        users.save(com.bank.digital_banking.module.auth.entity.User.builder().username(name).email(name + "@example.test")
                .password(template.getPassword()).roles(new java.util.HashSet<>(template.getRoles())).enabled(true).build());
        String token = login(name, "device-default-pair").path("accessToken").asText();
        var response = call("POST", "/accounts/pairs", token, Map.of("accountType", "CHECKING"));
        assertThat(response.statusCode()).as(response.body()).isEqualTo(201);
        var data = body(response).path("data");
        assertThat(data.path("testFundingApplied").asBoolean()).isFalse();
        assertThat(data.path("accounts").size()).isEqualTo(2);
        for (var account : data.path("accounts")) assertThat(account.path("balance").decimalValue()).isZero();
    }

    JsonNode login(String username, String device) throws Exception {
        requestOtp(username + "@example.test", "LOGIN");
        var response = call("POST", "/auth/login", null, Map.of(
                "usernameOrEmail", (username + "@example.test").toUpperCase(Locale.ROOT),
                "password", PASSWORD,
                "otpCode", SMTP.code(username + "@example.test"),
                "deviceFingerprint", device,
                "deviceName", "Android emulator",
                "deviceType", "ANDROID"
        ));
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        return body(response).path("data");
    }

    void requestOtp(String email, String purpose) throws Exception {
        var response = call("POST", "/auth/request-otp", null, Map.of("email", email, "purpose", purpose));
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
    }

    JsonNode body(HttpResponse<String> response) throws Exception {
        return json.readTree(response.body());
    }

    HttpResponse<String> call(String method, String path, String token, Object data) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1" + path))
                .timeout(Duration.ofSeconds(20));
        if (token != null) request.header("Authorization", "Bearer " + token);
        request.header("Idempotency-Key", UUID.randomUUID().toString());
        if (data != null) request.header("Content-Type", "application/json");

        return client.send(
                request.method(method, data == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(data))).build(),
                HttpResponse.BodyHandlers.ofString()
        );
    }
}
