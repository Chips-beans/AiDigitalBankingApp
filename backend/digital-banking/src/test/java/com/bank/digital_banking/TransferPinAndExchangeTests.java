package com.bank.digital_banking;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.transaction.dto.TransactionResponseDto;
import com.bank.digital_banking.module.transaction.entity.Transaction;
import com.bank.digital_banking.module.transaction.service.ExchangeRates;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import tools.jackson.databind.*;
import java.math.BigDecimal;
import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

@TestPropertySource(properties = "app.transfer.pin-proof-required=true")
class TransferPinAndExchangeTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired UserRepository users;
    final HttpClient client = HttpClient.newHttpClient();
    record Customer(String token, String name, String usd, String khr) {}

    @BeforeEach void limits() {
        jdbc.update("DELETE FROM otp_rate_limits");
        jdbc.update("DELETE FROM login_attempt_limits");
    }

    @Test void fixedRateRoundsKhrToUsdDownAndUsdToKhrExactly() {
        var rates = new ExchangeRates(new BigDecimal("4000"));
        assertThat(rates.forDebit(new BigDecimal("2.50"), "USD", "KHR").creditAmount()).isEqualByComparingTo("10000");
        assertThat(rates.forDebit(new BigDecimal("0.01"), "USD", "KHR").creditAmount()).isEqualByComparingTo("40");
        assertThat(rates.forDebit(new BigDecimal("10001"), "KHR", "USD").creditAmount()).isEqualByComparingTo("2.50");
        assertThat(rates.forDebit(new BigDecimal("40"), "KHR", "USD").creditAmount()).isEqualByComparingTo("0.01");
        assertThat(rates.forDebit(new BigDecimal("4001"), "KHR", "USD").creditAmount()).isEqualByComparingTo("1.00");
        assertThatThrownBy(() -> rates.forDebit(new BigDecimal("39"), "KHR", "USD"))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.getCode()).isEqualTo("AMOUNT_TOO_SMALL"));
        assertThatThrownBy(() -> rates.forDebit(BigDecimal.ONE, "KHR", "USD"))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.getCode()).isEqualTo("AMOUNT_TOO_SMALL"));
        var same = rates.forDebit(new BigDecimal("12.34"), "USD", "USD");
        assertThat(same.converted()).isFalse(); assertThat(same.creditAmount()).isEqualByComparingTo("12.34");
        // Fixed-amount requests must be payable exactly.
        assertThat(rates.forCredit(new BigDecimal("10000"), "USD", "KHR").debitAmount()).isEqualByComparingTo("2.50");
        assertThat(rates.forCredit(new BigDecimal("2.50"), "KHR", "USD").debitAmount()).isEqualByComparingTo("10000");
        assertThatThrownBy(() -> rates.forCredit(new BigDecimal("10001"), "USD", "KHR"))
                .isInstanceOfSatisfying(ApiException.class, e -> assertThat(e.getCode()).isEqualTo("CONVERSION_NOT_EXACT"));
        assertThatThrownBy(() -> new ExchangeRates(new BigDecimal("4000.5"))).isInstanceOf(IllegalStateException.class);
    }

    @Test void bankDepositsAreAttributedToKesorBank() {
        var dto = TransactionResponseDto.fromEntity(Transaction.builder().amount(new BigDecimal("200.00"))
                .currency("USD").referenceNumber("TXN-x").build());
        assertThat(dto.getSourceName()).isEqualTo("Kesor Bank");
        assertThat(dto.isBankSource()).isTrue();
        assertThat(dto.getCreditAmount()).isEqualByComparingTo("200.00");
        assertThat(dto.getCreditCurrency()).isEqualTo("USD");
        assertThat(dto.getExchangeRate()).isNull();
    }

    @Test void transfersNeedAOneTimeSessionBoundPinProofExceptForReplays() throws Exception {
        var alice = customer("pin.alice"); var bob = customer("pin.bob");
        fund(alice.usd(), "100.00");
        var body = Map.of("sourceAccountNumber", alice.usd(), "destinationAccountNumber", bob.usd(), "amount", "10.00", "currency", "USD");

        var missing = call("POST", "/transactions/transfer", alice.token(), key(), null, body);
        assertThat(missing.statusCode()).isEqualTo(403);
        assertThat(error(missing)).isEqualTo("TRANSFER_PIN_REQUIRED");
        var wrong = call("POST", "/auth/pin/transfer-proof", alice.token(), null, null, Map.of("pin", "9999"));
        assertThat(wrong.statusCode()).isEqualTo(403);
        assertThat(error(wrong)).isEqualTo("PIN_INVALID");
        assertThat(call("POST", "/auth/pin/transfer-proof", null, null, null, Map.of("pin", "0427")).statusCode()).isEqualTo(401);

        String proof = proof(alice);
        String key = key();
        var first = call("POST", "/transactions/transfer", alice.token(), key, proof, body);
        assertThat(first.statusCode()).as(first.body()).isEqualTo(200);
        // A completed request replays without another PIN, so lost responses stay recoverable.
        var replay = call("POST", "/transactions/transfer", alice.token(), key, null, body);
        assertThat(replay.statusCode()).isEqualTo(200);
        assertThat(data(replay)).isEqualTo(data(first));
        var reused = call("POST", "/transactions/transfer", alice.token(), key(), proof, body);
        assertThat(reused.statusCode()).isEqualTo(403);
        assertThat(error(reused)).isEqualTo("TRANSFER_PIN_REQUIRED");
        // Another customer's proof is useless.
        var stolen = call("POST", "/transactions/transfer", bob.token(), key(), proof(alice),
                Map.of("sourceAccountNumber", bob.usd(), "destinationAccountNumber", alice.usd(), "amount", "1.00", "currency", "USD"));
        assertThat(stolen.statusCode()).isEqualTo(403);
        assertThat(balance(alice.usd())).isEqualByComparingTo("90.00");
        assertThat(balance(bob.usd())).isEqualByComparingTo("10.00");
        // A failed transfer does not burn the proof.
        String retry = proof(alice);
        var tooMuch = call("POST", "/transactions/transfer", alice.token(), key(), retry,
                Map.of("sourceAccountNumber", alice.usd(), "destinationAccountNumber", bob.usd(), "amount", "500.00", "currency", "USD"));
        assertThat(tooMuch.statusCode()).isEqualTo(400);
        assertThat(call("POST", "/transactions/transfer", alice.token(), key(), retry, body).statusCode()).isEqualTo(200);
    }

    @Test void crossCurrencyTransfersConvertAtTheFixedRateAndShowBothNames() throws Exception {
        var alice = customer("fx.alice"); var bob = customer("fx.bob");
        fund(alice.khr(), "100000"); fund(alice.usd(), "10.00");

        var quote = data(call("GET", "/transactions/quote?sourceAccountNumber=" + alice.khr() + "&destinationAccountNumber="
                + bob.usd() + "&amount=10001", alice.token(), null, null, null));
        assertThat(quote.path("creditAmount").decimalValue()).isEqualByComparingTo("2.50");
        assertThat(quote.path("rate").decimalValue()).isEqualByComparingTo("4000");
        assertThat(quote.path("converted").asBoolean()).isTrue();

        var khrToUsd = call("POST", "/transactions/transfer", alice.token(), key(), proof(alice),
                Map.of("sourceAccountNumber", alice.khr(), "destinationAccountNumber", bob.usd(), "amount", "10001", "currency", "KHR"));
        assertThat(khrToUsd.statusCode()).as(khrToUsd.body()).isEqualTo(200);
        var receipt = data(khrToUsd);
        assertThat(receipt.path("amount").decimalValue()).isEqualByComparingTo("10001");
        assertThat(receipt.path("currency").asText()).isEqualTo("KHR");
        assertThat(receipt.path("creditAmount").decimalValue()).isEqualByComparingTo("2.50");
        assertThat(receipt.path("creditCurrency").asText()).isEqualTo("USD");
        assertThat(receipt.path("exchangeRate").decimalValue()).isEqualByComparingTo("4000");
        assertThat(receipt.path("sourceName").asText()).isEqualTo(alice.name());
        assertThat(receipt.path("destinationName").asText()).isEqualTo(bob.name());
        assertThat(balance(alice.khr())).isEqualByComparingTo("89999");
        assertThat(balance(bob.usd())).isEqualByComparingTo("2.50");

        var usdToKhr = call("POST", "/transactions/transfer", alice.token(), key(), proof(alice),
                Map.of("sourceAccountNumber", alice.usd(), "destinationAccountNumber", bob.khr(), "amount", "2.50", "currency", "USD"));
        assertThat(usdToKhr.statusCode()).as(usdToKhr.body()).isEqualTo(200);
        assertThat(balance(alice.usd())).isEqualByComparingTo("7.50");
        assertThat(balance(bob.khr())).isEqualByComparingTo("10000");

        var tooSmall = call("POST", "/transactions/transfer", alice.token(), key(), proof(alice),
                Map.of("sourceAccountNumber", alice.khr(), "destinationAccountNumber", bob.usd(), "amount", "39", "currency", "KHR"));
        assertThat(tooSmall.statusCode()).isEqualTo(400);
        assertThat(error(tooSmall)).isEqualTo("AMOUNT_TOO_SMALL");
        var wrongCurrency = call("POST", "/transactions/transfer", alice.token(), key(), proof(alice),
                Map.of("sourceAccountNumber", alice.khr(), "destinationAccountNumber", bob.usd(), "amount", "10", "currency", "USD"));
        assertThat(error(wrongCurrency)).isEqualTo("CURRENCY_MISMATCH");

        // The receiver's history shows the credited side and the sender's name.
        var history = data(call("GET", "/transactions/account/" + bob.usd(), bob.token(), null, null, null)).path("content");
        assertThat(history.get(0).path("creditAmount").decimalValue()).isEqualByComparingTo("2.50");
        assertThat(history.get(0).path("sourceName").asText()).isEqualTo(alice.name());
        // Customer-wide monthly income counts the USD actually received.
        var month = java.time.YearMonth.now(java.time.ZoneId.of("Asia/Phnom_Penh"));
        var overview = data(call("GET", "/analytics/monthly-overview?year=" + month.getYear() + "&month=" + month.getMonthValue()
                + "&currency=USD", bob.token(), null, null, null));
        assertThat(new BigDecimal(overview.path("totalIncome").asText())).isEqualByComparingTo("2.50");
    }

    @Test void fixedKhrQrRequestsArePaidExactlyFromUsdWallets() throws Exception {
        var payer = customer("qrfx.payer"); var shop = customer("qrfx.shop");
        fund(payer.usd(), "20.00");
        var qr = data(call("POST", "/payments/qr/generate", shop.token(), null, null,
                Map.of("accountNumber", shop.khr(), "currency", "KHR", "qrType", "DYNAMIC", "amount", "10000"))).path("qrString").asText();
        var paid = call("POST", "/payments/qr/transfer", payer.token(), key(), proof(payer),
                Map.of("sourceAccountNumber", payer.usd(), "qrString", qr, "currency", "USD"));
        assertThat(paid.statusCode()).as(paid.body()).isEqualTo(200);
        assertThat(balance(payer.usd())).isEqualByComparingTo("17.50");
        assertThat(balance(shop.khr())).isEqualByComparingTo("10000");

        var odd = data(call("POST", "/payments/qr/generate", shop.token(), null, null,
                Map.of("accountNumber", shop.khr(), "currency", "KHR", "qrType", "DYNAMIC", "amount", "10001"))).path("qrString").asText();
        var inexact = call("POST", "/payments/qr/transfer", payer.token(), key(), proof(payer),
                Map.of("sourceAccountNumber", payer.usd(), "qrString", odd, "currency", "USD"));
        assertThat(inexact.statusCode()).isEqualTo(400);
        assertThat(error(inexact)).isEqualTo("CONVERSION_NOT_EXACT");
        assertThat(call("POST", "/payments/qr/transfer", payer.token(), key(), null,
                Map.of("sourceAccountNumber", payer.usd(), "qrString", qr, "currency", "USD")).statusCode()).isEqualTo(403);
    }

    @Test void recipientLookupReturnsActiveHoldersOnly() throws Exception {
        var alice = customer("lookup.alice"); var bob = customer("lookup.bob");
        var found = call("GET", "/accounts/lookup?number=" + bob.khr(), alice.token(), null, null, null);
        assertThat(found.statusCode()).as(found.body()).isEqualTo(200);
        assertThat(data(found).path("displayName").asText()).isEqualTo(bob.name());
        assertThat(data(found).path("currency").asText()).isEqualTo("KHR");
        assertThat(data(found).path("hasPhoto").asBoolean()).isFalse();
        assertThat(call("GET", "/accounts/lookup/photo?number=" + bob.khr(), alice.token(), null, null, null).statusCode()).isEqualTo(404);
        assertThat(call("GET", "/accounts/lookup?number=1234567890123", alice.token(), null, null, null).statusCode()).isEqualTo(404);
        assertThat(call("GET", "/accounts/lookup?number=12ab", alice.token(), null, null, null).statusCode()).isEqualTo(400);
        assertThat(call("GET", "/accounts/lookup?number=" + bob.khr(), null, null, null, null).statusCode()).isEqualTo(401);
        jdbc.update("UPDATE accounts SET status='FROZEN' WHERE account_number=?", bob.usd());
        assertThat(call("GET", "/accounts/lookup?number=" + bob.usd(), alice.token(), null, null, null).statusCode()).isEqualTo(404);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM audit_logs WHERE action='RECIPIENT_LOOKUP' AND target_resource_id LIKE '******%'", Integer.class)).isPositive();
    }

    Customer customer(String prefix) throws Exception {
        var template = users.findByUsername("alice.demo").orElseThrow();
        String name = prefix + "." + UUID.randomUUID().toString().substring(0, 8);
        users.save(User.builder().username(name).email(name + "@example.test").password(template.getPassword())
                .firstName("Sok").lastName(prefix.replace('.', ' ')).roles(new HashSet<>(template.getRoles()))
                .enabled(true).profileComplete(true).build());
        call("POST", "/auth/request-otp", null, null, null, Map.of("email", name + "@example.test", "purpose", "LOGIN"));
        var login = call("POST", "/auth/login", null, null, null, Map.of("usernameOrEmail", name, "password", PASSWORD,
                "otpCode", SMTP.code(name + "@example.test"), "deviceFingerprint", name, "deviceName", "QA"));
        assertThat(login.statusCode()).as(login.body()).isEqualTo(200);
        String access = data(login).path("accessToken").asText();
        var prepare = call("POST", "/auth/pin/prepare", access, null, null, null);
        assertThat(prepare.statusCode()).as(prepare.body()).isEqualTo(200);
        var setup = call("POST", "/auth/pin/setup", null, null, null,
                Map.of("ticket", data(prepare).path("ticket").asText(), "pin", "0427", "confirmPin", "0427"));
        assertThat(setup.statusCode()).as(setup.body()).isEqualTo(200);
        String token = data(setup).path("accessToken").asText();
        var pair = data(call("POST", "/accounts/pairs", token, key(), null, Map.of("accountType", "SAVINGS"))).path("accounts");
        return new Customer(token, "Sok " + prefix.replace('.', ' '), pair.get(0).path("accountNumber").asText(),
                pair.get(1).path("accountNumber").asText());
    }
    String proof(Customer customer) throws Exception {
        var response = call("POST", "/auth/pin/transfer-proof", customer.token(), null, null, Map.of("pin", "0427"));
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        assertThat(data(response).path("expiresInSeconds").asInt()).isEqualTo(120);
        return data(response).path("proof").asText();
    }
    void fund(String account, String amount) { jdbc.update("UPDATE accounts SET balance=? WHERE account_number=?", new BigDecimal(amount), account); }
    BigDecimal balance(String account) { return jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number=?", BigDecimal.class, account); }
    String key() { return UUID.randomUUID().toString(); }
    JsonNode data(HttpResponse<String> response) { return json.readTree(response.body()).path("data"); }
    String error(HttpResponse<String> response) { return json.readTree(response.body()).path("error").asText(); }
    HttpResponse<String> call(String method, String path, String token, String key, String proof, Object payload) throws Exception {
        var r = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1" + path)).timeout(Duration.ofSeconds(20));
        if (token != null) r.header("Authorization", "Bearer " + token);
        if (key != null) r.header("Idempotency-Key", key);
        if (proof != null) r.header("X-Pin-Proof", proof);
        if (payload != null) r.header("Content-Type", "application/json");
        return client.send(r.method(method, payload == null ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload))).build(), HttpResponse.BodyHandlers.ofString());
    }
}
