package com.bank.digital_banking;

import com.bank.digital_banking.module.account.service.OpeningFundingPolicy;
import com.bank.digital_banking.module.payment.qr.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.env.MockEnvironment;
import tools.jackson.databind.*;
import java.net.*;
import java.net.http.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import static org.assertj.core.api.Assertions.*;

@SpringBootTest(classes = DigitalBankingApplication.class, webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "app.dev.opening-funding.enabled=true")
class AccountPairQrTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired QrCodeEngine engine;
    private final HttpClient client = HttpClient.newHttpClient();
    String alice, bob;

    @BeforeEach void loginCustomers() throws Exception {
        jdbc.update("DELETE FROM otp_rate_limits");
        jdbc.update("DELETE FROM login_attempt_limits");
        alice = login("alice.demo"); bob = login("bob.demo");
    }
    @Test void fundedPairsReplayConflictAndPreserveExistingAccounts() throws Exception {
        String key = UUID.randomUUID().toString();
        var before = jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number='9000000001'", java.math.BigDecimal.class);
        var first = call("POST", "/accounts/pairs", alice, key, Map.of("accountType", "SAVINGS"));
        assertThat(first.statusCode()).as(first.body()).isEqualTo(201);
        var data = data(first);
        assertThat(data.path("testFundingApplied").asBoolean()).isTrue();
        assertThat(data.path("accounts").size()).isEqualTo(2);
        assertThat(data.path("accounts").get(0).path("balance").decimalValue()).isEqualByComparingTo("200.00");
        assertThat(data.path("accounts").get(1).path("balance").decimalValue()).isEqualByComparingTo("100000");
        assertThat(data(call("POST", "/accounts/pairs", alice, key, Map.of("accountType", "SAVINGS")))).isEqualTo(data);
        assertThat(call("POST", "/accounts/pairs", alice, key, Map.of("accountType", "CHECKING")).statusCode()).isEqualTo(409);
        assertThat(call("POST", "/accounts/pairs", alice, null, Map.of("accountType", "SAVINGS")).statusCode()).isEqualTo(400);
        for (var account : data.path("accounts")) {
            assertThat(jdbc.queryForObject("SELECT count(*) FROM transactions t JOIN accounts a ON a.id=t.destination_account_id WHERE a.account_number=? AND t.operation='TEST_OPENING_CREDIT'", Integer.class, account.path("accountNumber").asText())).isEqualTo(1);
        }
        assertThat(jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number='9000000001'", java.math.BigDecimal.class)).isEqualByComparingTo(before);
        assertThat(data(call("GET", "/accounts/opening-policy", alice, null, null)).path("testFundingEnabled").asBoolean()).isTrue();
    }
    @Test void concurrentOpeningCreatesOnePair() throws Exception {
        String key = UUID.randomUUID().toString();
        try (var pool = Executors.newFixedThreadPool(2)) {
            var a = pool.submit(() -> call("POST", "/accounts/pairs", alice, key, Map.of("accountType", "PAYROLL")));
            var b = pool.submit(() -> call("POST", "/accounts/pairs", alice, key, Map.of("accountType", "PAYROLL")));
            var ar = a.get(); var br = b.get();
            assertThat(ar.statusCode()).as(ar.body()).isEqualTo(201);
            assertThat(br.statusCode()).as(br.body()).isEqualTo(201);
            assertThat(data(ar)).isEqualTo(data(br));
        }
    }
    @Test void secondAccountFailureRollsBackFirstAccountCreditAndRequest() throws Exception {
        long before = jdbc.queryForObject("SELECT count(*) FROM accounts", Long.class);
        long postings = jdbc.queryForObject("SELECT count(*) FROM transactions", Long.class);
        String key = UUID.randomUUID().toString();
        jdbc.execute("ALTER TABLE accounts ADD CONSTRAINT qa_reject_new_khr CHECK(currency <> 'KHR') NOT VALID");
        try {
            assertThat(call("POST", "/accounts/pairs", alice, key, Map.of("accountType", "SAVINGS")).statusCode()).isGreaterThanOrEqualTo(400);
            assertThat(jdbc.queryForObject("SELECT count(*) FROM accounts", Long.class)).isEqualTo(before);
            assertThat(jdbc.queryForObject("SELECT count(*) FROM transactions", Long.class)).isEqualTo(postings);
            assertThat(jdbc.queryForObject("SELECT count(*) FROM account_opening_requests WHERE request_key=?", Integer.class, key)).isZero();
        } finally { jdbc.execute("ALTER TABLE accounts DROP CONSTRAINT qa_reject_new_khr"); }
    }
    @Test void policyBlocksProductionIncludingMixedProfilesAndDefaultsToZero() {
        for (String[] profiles : List.of(new String[]{"prod"}, new String[]{"dev", "production"}, new String[]{"prod", "local"}, new String[]{"unknown"})) {
            var env = new MockEnvironment(); env.setActiveProfiles(profiles);
            assertThatThrownBy(() -> new OpeningFundingPolicy(env, true)).isInstanceOf(IllegalStateException.class);
        }
        var env = new MockEnvironment(); env.setActiveProfiles("staging");
        assertThat(new OpeningFundingPolicy(env, true).amount("KHR")).isEqualByComparingTo("100000");
        assertThat(new OpeningFundingPolicy(env, false).amount("USD")).isZero();
    }
    @Test void customerJourneyBothCurrenciesStaticReuseAndDynamicRetry() throws Exception {
        var sender = pair(bob); var receiver = pair(alice);
        for (int i = 0; i < 2; i++) {
            String source = sender.get(i).path("accountNumber").asText();
            String destination = receiver.get(i).path("accountNumber").asText();
            String currency = i == 0 ? "USD" : "KHR", amount = i == 0 ? "10.00" : "10000";
            String qr = generate(alice, destination, currency, null);
            assertThat(generate(alice, destination, currency, null)).isEqualTo(qr);
            assertThat(data(call("POST", "/payments/qr/scan", bob, null, Map.of("qrString", qr))).path("destinationAccountNumber").asText()).isEqualTo(destination);
            var payload = Map.of("sourceAccountNumber", source, "qrString", qr, "amount", amount, "currency", currency);
            String key = UUID.randomUUID().toString();
            var first = call("POST", "/payments/qr/transfer", bob, key, payload);
            assertThat(first.statusCode()).as(first.body()).isEqualTo(200);
            assertThat(data(first).path("transaction").path("status").asText()).isEqualTo("SUCCESS");
            assertThat(data(call("POST", "/payments/qr/transfer", bob, key, payload))).isEqualTo(data(first));
            assertThat(call("POST", "/payments/qr/transfer", bob, UUID.randomUUID().toString(), payload).statusCode()).isEqualTo(200);
            var initial = new java.math.BigDecimal(i == 0 ? "200" : "100000");
            assertThat(jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number=?", java.math.BigDecimal.class, source)).isEqualByComparingTo(initial.subtract(new java.math.BigDecimal(amount).multiply(new java.math.BigDecimal(2))));
            assertThat(jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number=?", java.math.BigDecimal.class, destination)).isEqualByComparingTo(initial.add(new java.math.BigDecimal(amount).multiply(new java.math.BigDecimal(2))));
            String fixed = generate(alice, destination, currency, amount);
            assertThat(generate(alice, destination, currency, amount)).isNotEqualTo(fixed);
            var fixedPayload = Map.of("sourceAccountNumber", source, "qrString", fixed, "amount", amount, "currency", currency);
            key = UUID.randomUUID().toString();
            first = call("POST", "/payments/qr/transfer", bob, key, fixedPayload);
            assertThat(first.statusCode()).as(first.body()).isEqualTo(200);
            assertThat(data(call("POST", "/payments/qr/transfer", bob, key, fixedPayload))).isEqualTo(data(first));
            assertThat(call("POST", "/payments/qr/transfer", bob, UUID.randomUUID().toString(), fixedPayload).statusCode()).isEqualTo(409);
            var status = json.readTree(call("GET", "/payments/verify/" + engine.parse(fixed).getQrHash(), alice, null, null).body());
            assertThat(status.path("success").asBoolean()).isTrue();
            assertThat(status.path("isPaid").asBoolean()).isTrue();
            assertThat(jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number=?", java.math.BigDecimal.class, source)).isEqualByComparingTo(initial.subtract(new java.math.BigDecimal(amount).multiply(new java.math.BigDecimal(3))));
            assertThat(jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number=?", java.math.BigDecimal.class, destination)).isEqualByComparingTo(initial.add(new java.math.BigDecimal(amount).multiply(new java.math.BigDecimal(3))));
            var history = data(call("GET", "/transactions/account/" + source, bob, null, null));
            assertThat(history.path("totalElements").asInt()).isEqualTo(4);
        }
    }
    @Test void concurrentFixedPaymentPostsExactlyOnceAndStaticGenerationIsStable() throws Exception {
        var sender = pair(bob).get(0); var receiver = pair(alice).get(0);
        String destination = receiver.path("accountNumber").asText();
        try (var pool = Executors.newFixedThreadPool(2)) {
            var a = pool.submit(() -> generate(alice, destination, "USD", null));
            var b = pool.submit(() -> generate(alice, destination, "USD", null));
            assertThat(a.get()).isEqualTo(b.get());
            String fixed = generate(alice, destination, "USD", "10.00");
            var payload = Map.of("sourceAccountNumber", sender.path("accountNumber").asText(), "qrString", fixed, "amount", "10.00", "currency", "USD");
            var x = pool.submit(() -> call("POST", "/payments/qr/transfer", bob, UUID.randomUUID().toString(), payload).statusCode());
            var y = pool.submit(() -> call("POST", "/payments/qr/transfer", bob, UUID.randomUUID().toString(), payload).statusCode());
            assertThat(List.of(x.get(), y.get())).containsExactlyInAnyOrder(200, 409);
            assertThat(jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number=?", java.math.BigDecimal.class, destination)).isEqualByComparingTo("210.00");
        }
    }
    @Test void qrRejectsOwnershipPrecisionCurrencyAndUnregisteredPayloads() throws Exception {
        var receiver = pair(alice);
        String usd = receiver.get(0).path("accountNumber").asText(), khr = receiver.get(1).path("accountNumber").asText();
        assertThat(call("POST", "/payments/qr/generate", bob, null, Map.of("accountNumber", usd, "currency", "USD")).statusCode()).isEqualTo(404);
        assertThat(call("POST", "/payments/qr/generate", alice, null, Map.of("accountNumber", usd, "currency", "KHR")).statusCode()).isEqualTo(400);
        for (var bad : List.of(Map.of("accountNumber", usd, "currency", "USD", "amount", "1.001"), Map.of("accountNumber", khr, "currency", "KHR", "amount", "1.5")))
            assertThat(call("POST", "/payments/qr/generate", alice, null, bad).statusCode()).isEqualTo(400);
        var unknown = engine.generate(new QrCodeEngine.GenerateOptions(usd, "Unregistered", null, "USD", null, null, null, false));
        assertThat(call("POST", "/payments/qr/scan", bob, null, Map.of("qrString", unknown.getQrString())).statusCode()).isEqualTo(400);
        var sender = pair(bob);
        String fixed = generate(alice, usd, "USD", "10.00");
        var payload = Map.of("sourceAccountNumber", sender.get(0).path("accountNumber").asText(), "qrString", fixed, "amount", "11", "currency", "USD");
        assertThat(call("POST", "/payments/qr/transfer", bob, "mismatch", payload).statusCode()).isEqualTo(400);
        assertThat(call("POST", "/payments/qr/transfer", bob, null, payload).statusCode()).isEqualTo(400);
        payload = Map.of("sourceAccountNumber", sender.get(1).path("accountNumber").asText(), "qrString", fixed, "amount", "10", "currency", "KHR");
        assertThat(call("POST", "/payments/qr/transfer", bob, "currency", payload).statusCode()).isEqualTo(400);
    }

    @Test void concurrentSameKeyQrRequestsReturnOneReceiptAndManualKeysAreSeparate() throws Exception {
        var source = pair(bob).get(0).path("accountNumber").asText();
        var destination = pair(alice).get(0).path("accountNumber").asText();
        String key = UUID.randomUUID().toString();
        String qr = generate(alice, destination, "USD", "10.00");
        var payload = Map.of("sourceAccountNumber", source, "qrString", qr, "amount", "10.00", "currency", "USD");
        call("POST", "/transactions/transfer", bob, key, Map.of("sourceAccountNumber", source, "destinationAccountNumber", destination, "amount", "10.00", "currency", "USD"));
        try (var pool = Executors.newFixedThreadPool(2)) {
            var a = pool.submit(() -> call("POST", "/payments/qr/transfer", bob, key, payload));
            var b = pool.submit(() -> call("POST", "/payments/qr/transfer", bob, key, payload));
            var ar = a.get(); var br = b.get();
            assertThat(ar.statusCode()).as(ar.body()).isEqualTo(200);
            assertThat(br.statusCode()).as(br.body()).isEqualTo(200);
            assertThat(data(ar)).isEqualTo(data(br));
            assertThat(jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number=?", java.math.BigDecimal.class, destination)).isEqualByComparingTo("220.00");
        }
        assertThat(call("POST", "/payments/qr/transfer", bob, key, Map.of("sourceAccountNumber", source, "qrString", qr, "amount", "11.00", "currency", "USD")).statusCode()).isEqualTo(409);
    }
    JsonNode pair(String token) throws Exception { return data(call("POST", "/accounts/pairs", token, UUID.randomUUID().toString(), Map.of("accountType", "SAVINGS"))).path("accounts"); }
    String generate(String token, String account, String currency, String amount) throws Exception {
        var payload = new HashMap<String,Object>(); payload.put("accountNumber", account); payload.put("currency", currency); payload.put("qrType", amount == null ? "STATIC" : "DYNAMIC");
        if (amount != null) payload.put("amount", amount);
        var response = call("POST", "/payments/qr/generate", token, null, payload);
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        return data(response).path("qrString").asText();
    }
    String login(String user) throws Exception {
        call("POST", "/auth/request-otp", null, null, Map.of("email", user + "@example.test", "purpose", "LOGIN"));
        var r = call("POST", "/auth/login", null, null, Map.of("usernameOrEmail", user, "password", PASSWORD, "otpCode", SMTP.code(user + "@example.test"), "deviceFingerprint", "pairs-" + user, "deviceName", "QA"));
        assertThat(r.statusCode()).as(r.body()).isEqualTo(200); return data(r).path("accessToken").asText();
    }
    JsonNode data(HttpResponse<String> response) { return json.readTree(response.body()).path("data"); }
    HttpResponse<String> call(String method, String path, String token, String key, Object payload) throws Exception {
        var r = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1" + path)).timeout(Duration.ofSeconds(20));
        if (token != null) r.header("Authorization", "Bearer " + token);
        if (key != null) r.header("Idempotency-Key", key);
        if (payload != null) r.header("Content-Type", "application/json");
        return client.send(r.method(method, payload == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload))).build(), HttpResponse.BodyHandlers.ofString());
    }
}
