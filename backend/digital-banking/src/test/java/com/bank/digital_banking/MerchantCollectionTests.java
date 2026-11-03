package com.bank.digital_banking;

import com.bank.digital_banking.module.account.service.AccountService;
import com.bank.digital_banking.module.auth.dto.TokenResponseDto;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.service.*;
import com.bank.digital_banking.module.merchant.service.MerchantCollectionService;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.*;

import java.math.BigDecimal;
import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import static org.assertj.core.api.Assertions.*;

/** M5/M6 over HTTP: a funded payer pays a registered shop. Same context as MerchantShopTests. */
@SpringBootTest(classes = DigitalBankingApplication.class, webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "app.dev.opening-funding.enabled=true")
class MerchantCollectionTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired UserRepository users;
    @Autowired RoleRepository roles;
    @Autowired SessionService sessions;
    @Autowired DeviceService devices;
    @Autowired AccountService accounts;
    @Autowired PlatformTransactionManager txManager;
    @Autowired MerchantCollectionService collections;
    final HttpClient http = HttpClient.newHttpClient();
    record Shop(long owner, String merchant, String customer, String code, String khr, String usd) {}
    record Payer(long id, String token, String usd, String khr) {}

    @BeforeEach void limits() { jdbc.update("DELETE FROM merchant_auth_limits"); }

    @Test void fixedRequestIsPaidOnceAcrossCurrenciesAndFeedsDashboardWalletAndHistory() throws Exception {
        var shop = shop(); var payer = payer();
        var created = request(shop, key(), Map.of("currency", "KHR", "amount", "10000", "orderReference", "Table 4"));
        assertThat(created.statusCode()).as(created.body()).isEqualTo(201);
        var r = data(created);
        assertThat(r.path("status").asText()).isEqualTo("WAITING");
        assertThat(r.path("reference").asText()).matches("PR[A-Z2-9]{10}");
        assertThat(r.path("amount").asText()).isEqualTo("10000");
        String qr = r.path("qrString").asText();

        var scan = data(call("POST", "/payments/qr/scan", payer.token(), Map.of("qrString", qr)));
        assertThat(scan.path("destinationAccountName").asText()).isEqualTo("Sokha Coffee");
        assertThat(scan.toString()).doesNotContain("Synthetic Owner");
        assertThat(scan.path("merchant").path("storeName").asText()).isEqualTo("Sokha Coffee");
        assertThat(scan.path("merchant").path("verified").asBoolean()).isTrue();
        assertThat(scan.path("expiresAt").isNull()).isFalse();

        // Paying a KHR request from the USD wallet debits the exact fixed-rate equivalent.
        var paid = pay(payer, payer.usd(), qr, null, "USD", key());
        assertThat(paid.statusCode()).as(paid.body()).isEqualTo(200);
        assertThat(data(paid).path("destinationAccountName").asText()).isEqualTo("Sokha Coffee");
        assertThat(balance(payer.usd())).isEqualByComparingTo("197.50");
        assertThat(balance(shop.khr())).isEqualByComparingTo("10000");

        var statusResponse = call("GET", "/merchants/me/payment-requests/" + r.path("requestId").asText(), shop.merchant(), null);
        assertThat(statusResponse.statusCode()).as(statusResponse.body()).isEqualTo(200);
        var status = data(statusResponse);
        assertThat(status.path("status").asText()).isEqualTo("PAID");
        assertThat(status.path("qrString").isNull()).isTrue();
        var receipt = status.path("receipt");
        assertThat(receipt.path("amount").asText()).isEqualTo("10000");
        assertThat(receipt.path("paidCurrency").asText()).isEqualTo("USD");
        assertThat(receipt.path("paidAmount").asText()).isEqualTo("2.50");
        assertThat(receipt.path("payerName").asText()).isEqualTo("Payer");
        assertThat(receipt.path("payerAccount").asText()).isEqualTo("•••• " + payer.usd().substring(payer.usd().length() - 4));
        assertThat(receipt.path("orderReference").asText()).isEqualTo("Table 4");

        assertThat(error(pay(payer, payer.khr(), qr, null, "KHR", key()))).isEqualTo("PAYMENT_ALREADY_COMPLETED");
        assertThat(balance(shop.khr())).isEqualByComparingTo("10000");

        var dashboard = data(call("GET", "/merchants/me/dashboard", shop.merchant(), null));
        var today = dashboard.path("today");
        assertThat(today.get(0).path("currency").asText()).isEqualTo("KHR");
        assertThat(today.get(0).path("count").asLong()).isEqualTo(1);
        assertThat(today.get(0).path("gross").asText()).isEqualTo("10000");
        assertThat(today.get(1).path("gross").asText()).isEqualTo("0.00");
        assertThat(dashboard.path("recent")).hasSize(1);
        assertThat(dashboard.path("profile").path("wallets").get(0).path("balance").asText()).isEqualTo("10000");

        var wallet = data(call("GET", "/merchants/me/wallets/" + shop.khr(), shop.merchant(), null));
        assertThat(wallet.path("activity").get(0).path("kind").asText()).isEqualTo("QR_PAYMENT");
        assertThat(wallet.path("activity").get(0).path("direction").asText()).isEqualTo("IN");
        assertThat(wallet.path("activity").get(0).path("amount").asText()).isEqualTo("10000");

        // The payer's own history names the shop, not its owner.
        var history = data(call("GET", "/transactions/account/" + payer.usd(), payer.token(), null)).path("content");
        assertThat(history.get(0).path("destinationName").asText()).isEqualTo("Sokha Coffee");
    }

    @Test void cancelledAndExpiredRequestsCannotBePaid() throws Exception {
        var shop = shop(); var payer = payer();
        var cancelled = data(request(shop, key(), Map.of("currency", "USD", "amount", "4.50")));
        var result = data(call("POST", "/merchants/me/payment-requests/" + cancelled.path("requestId").asText() + "/cancel", shop.merchant(), null));
        assertThat(result.path("status").asText()).isEqualTo("CANCELLED");
        assertThat(error(call("POST", "/payments/qr/scan", payer.token(), Map.of("qrString", cancelled.path("qrString").asText()))))
                .isEqualTo("PAYMENT_REQUEST_CANCELLED");
        assertThat(error(pay(payer, payer.usd(), cancelled.path("qrString").asText(), null, "USD", key())))
                .isEqualTo("PAYMENT_REQUEST_CANCELLED");

        var expiring = data(request(shop, key(), Map.of("currency", "USD", "amount", "1.25")));
        UUID id = UUID.fromString(expiring.path("requestId").asText());
        jdbc.update("UPDATE merchant_payment_requests SET created_at=created_at-INTERVAL '1 hour',expires_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=?", id);
        assertThat(error(pay(payer, payer.usd(), expiring.path("qrString").asText(), null, "USD", key())))
                .isEqualTo("PAYMENT_REQUEST_EXPIRED");
        assertThat(data(call("GET", "/merchants/me/payment-requests/" + id, shop.merchant(), null)).path("status").asText())
                .isEqualTo("EXPIRED");
        assertThat(balance(payer.usd())).isEqualByComparingTo("200.00");
        assertThat(balance(shop.usd())).isEqualByComparingTo("0.00");

        var swept = data(request(shop, key(), Map.of("currency", "KHR", "amount", "500")));
        UUID sweptId = UUID.fromString(swept.path("requestId").asText());
        jdbc.update("UPDATE merchant_payment_requests SET created_at=created_at-INTERVAL '1 hour',expires_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=?", sweptId);
        collections.expireWaiting();
        assertThat(jdbc.queryForObject("SELECT status FROM merchant_payment_requests WHERE id=?", String.class, sweptId)).isEqualTo("EXPIRED");
    }

    @Test void payingAndCancellingTheSameRequestHaveExactlyOneOutcome() throws Exception {
        for (int round = 0; round < 3; round++) {
            var shop = shop(); var payer = payer();
            var r = data(request(shop, key(), Map.of("currency", "USD", "amount", "5.00")));
            var results = race(() -> pay(payer, payer.usd(), r.path("qrString").asText(), null, "USD", key()),
                    () -> call("POST", "/merchants/me/payment-requests/" + r.path("requestId").asText() + "/cancel", shop.merchant(), null));
            String finalStatus = data(results.get(1)).path("status").asText();
            assertThat(results.get(1).statusCode()).isEqualTo(200);
            if (results.get(0).statusCode() == 200) {
                assertThat(finalStatus).isEqualTo("PAID");
                assertThat(balance(shop.usd())).isEqualByComparingTo("5.00");
                assertThat(collectionsOf(shop)).isEqualTo(1);
            } else {
                assertThat(finalStatus).isEqualTo("CANCELLED");
                assertThat(error(results.get(0))).isEqualTo("PAYMENT_REQUEST_CANCELLED");
                assertThat(balance(shop.usd())).isEqualByComparingTo("0.00");
                assertThat(balance(payer.usd())).isEqualByComparingTo("200.00");
                assertThat(collectionsOf(shop)).isZero();
            }
        }
    }

    @Test void requestCreationIsIdempotentAndValidated() throws Exception {
        var shop = shop(); String key = key();
        var first = request(shop, key, Map.of("currency", "USD", "amount", "2.5"));
        assertThat(first.statusCode()).isEqualTo(201);
        var replay = request(shop, key, Map.of("currency", "usd", "amount", "2.50"));
        assertThat(replay.statusCode()).as(replay.body()).isEqualTo(200);
        assertThat(data(replay).path("requestId").asText()).isEqualTo(data(first).path("requestId").asText());
        assertThat(error(request(shop, key, Map.of("currency", "USD", "amount", "3.00")))).isEqualTo("IDEMPOTENCY_CONFLICT");
        assertThat(error(request(shop, key(), Map.of("currency", "KHR", "amount", "10.5")))).isEqualTo("INVALID_AMOUNT");
        assertThat(request(shop, key(), Map.of("currency", "USD", "amount", "0")).statusCode()).isEqualTo(400);
        assertThat(request(shop, key(), Map.of("currency", "EUR", "amount", "1")).statusCode()).isEqualTo(400);
        assertThat(request(shop, key(), Map.of("currency", "USD", "amount", "1", "accountNumber", shop.usd())).statusCode()).isEqualTo(400);
        assertThat(request(shop, key(), Map.of("currency", "USD", "amount", "1", "orderReference", "x".repeat(51))).statusCode()).isEqualTo(400);
        assertThat(error(call("POST", "/merchants/me/payment-requests", shop.merchant(), Map.of("currency", "USD", "amount", "1"))))
                .isEqualTo("IDEMPOTENCY_KEY_REQUIRED");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_payment_requests WHERE owner_user_id=?", Long.class, shop.owner())).isEqualTo(1);
    }

    @Test void reusableShopQrTakesAnyAmountAndIsStable() throws Exception {
        var shop = shop(); var payer = payer();
        var qr = data(call("GET", "/merchants/me/qr?currency=USD", shop.merchant(), null));
        assertThat(qr.path("accountNumber").asText()).isEqualTo(shop.usd());
        assertThat(data(call("GET", "/merchants/me/qr?currency=USD", shop.merchant(), null)).path("qrString").asText())
                .isEqualTo(qr.path("qrString").asText());
        var scan = data(call("POST", "/payments/qr/scan", payer.token(), Map.of("qrString", qr.path("qrString").asText())));
        assertThat(scan.path("merchant").path("merchantId").asText()).isEqualTo(shop.code());
        assertThat(scan.path("isDynamic").asBoolean()).isFalse();
        var paid = pay(payer, payer.usd(), qr.path("qrString").asText(), "3.00", "USD", key());
        assertThat(paid.statusCode()).as(paid.body()).isEqualTo(200);
        var dashboard = data(call("GET", "/merchants/me/dashboard", shop.merchant(), null));
        assertThat(dashboard.path("today").get(1).path("count").asLong()).isEqualTo(1);
        assertThat(dashboard.path("today").get(1).path("gross").asText()).isEqualTo("3.00");
        assertThat(dashboard.path("recent").get(0).path("requestReference").isNull()).isTrue();
    }

    @Test void shopsAreIsolatedAndRestrictedShopsCannotCollect() throws Exception {
        var shop = shop(); var other = shop(); var payer = payer();
        var r = data(request(shop, key(), Map.of("currency", "USD", "amount", "1.00")));
        assertThat(call("GET", "/merchants/me/payment-requests/" + r.path("requestId").asText(), other.merchant(), null).statusCode()).isEqualTo(404);
        assertThat(call("POST", "/merchants/me/payment-requests/" + r.path("requestId").asText() + "/cancel", other.merchant(), null).statusCode()).isEqualTo(404);
        assertThat(call("GET", "/merchants/me/wallets/" + shop.usd(), other.merchant(), null).statusCode()).isEqualTo(404);
        assertThat(call("GET", "/merchants/me/wallets/" + payer.usd(), shop.merchant(), null).statusCode()).isEqualTo(404);
        assertThat(error(call("GET", "/merchants/me/dashboard", shop.customer(), null))).isEqualTo("MERCHANT_SESSION_REQUIRED");
        assertThat(error(call("GET", "/payments/merchants/" + shop.code() + "/logo", shop.merchant(), null))).isEqualTo("CUSTOMER_SESSION_REQUIRED");

        var staticQr = data(call("GET", "/merchants/me/qr?currency=USD", shop.merchant(), null)).path("qrString").asText();
        jdbc.update("UPDATE merchants SET status='SUSPENDED' WHERE owner_user_id=?", shop.owner());
        assertThat(error(request(shop, key(), Map.of("currency", "USD", "amount", "1.00")))).isEqualTo("MERCHANT_INACTIVE");
        assertThat(error(call("GET", "/merchants/me/qr?currency=USD", shop.merchant(), null))).isEqualTo("MERCHANT_INACTIVE");
        assertThat(error(call("POST", "/payments/qr/scan", payer.token(), Map.of("qrString", staticQr)))).isEqualTo("MERCHANT_INACTIVE");
        assertThat(error(pay(payer, payer.usd(), r.path("qrString").asText(), null, "USD", key()))).isEqualTo("MERCHANT_INACTIVE");
        var restricted = data(call("GET", "/merchants/me/dashboard", shop.merchant(), null));
        assertThat(restricted.path("profile").path("onboardingState").asText()).isEqualTo("RESTRICTED");
        assertThat(balance(payer.usd())).isEqualByComparingTo("200.00");
    }

    @Test void businessWalletsStayPrivateAndOnlyReceiveThroughQr() throws Exception {
        var shop = shop(); var payer = payer();
        assertThat(call("GET", "/accounts/lookup?number=" + shop.usd(), payer.token(), null).statusCode()).isEqualTo(404);
        assertThat(error(call("POST", "/payments/qr/generate", shop.customer(),
                Map.of("accountNumber", shop.usd(), "currency", "USD")))).isEqualTo("MERCHANT_QR_IN_MERCHANT_APP");
        jdbc.update("UPDATE accounts SET balance=10 WHERE account_number=?", shop.usd());
        var debit = call("POST", "/transactions/transfer", shop.customer(), Map.of("sourceAccountNumber", shop.usd(),
                "destinationAccountNumber", payer.usd(), "amount", "1.00", "currency", "USD"), Map.of("Idempotency-Key", key()));
        assertThat(error(debit)).isEqualTo("MERCHANT_WALLET_RESTRICTED");
        assertThat(balance(shop.usd())).isEqualByComparingTo("10.00");
    }

    @Test void customersSeeOnlyAnActiveShopsLogo() throws Exception {
        var shop = shop(); var payer = payer();
        assertThat(call("GET", "/payments/merchants/" + shop.code() + "/logo", payer.token(), null).statusCode()).isEqualTo(404);
        var image = new java.awt.image.BufferedImage(40, 40, java.awt.image.BufferedImage.TYPE_INT_RGB);
        var png = new java.io.ByteArrayOutputStream(); javax.imageio.ImageIO.write(image, "png", png);
        String boundary = "m6" + UUID.randomUUID().toString().replace("-", "");
        var body = new java.io.ByteArrayOutputStream();
        body.write(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"logo\"; filename=\"logo.png\"\r\n"
                + "Content-Type: image/png\r\n\r\n").getBytes());
        body.write(png.toByteArray());
        body.write(("\r\n--" + boundary + "--\r\n").getBytes());
        var uploaded = http.send(HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1/merchants/me/logo-uploads"))
                .header("Authorization", "Bearer " + shop.merchant()).header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .POST(HttpRequest.BodyPublishers.ofByteArray(body.toByteArray())).build(), HttpResponse.BodyHandlers.ofString());
        assertThat(uploaded.statusCode()).as(uploaded.body()).isEqualTo(201);
        var attached = call("PATCH", "/merchants/me/profile", shop.merchant(),
                Map.of("version", 0, "stagedLogoId", data(uploaded).path("logoId").asText()));
        assertThat(attached.statusCode()).as(attached.body()).isEqualTo(200);
        var preview = call("GET", "/payments/merchants/" + shop.code() + "/logo", payer.token(), null);
        assertThat(preview.statusCode()).as(preview.body()).isEqualTo(200);
        assertThat(data(preview).path("contentType").asText()).isEqualTo("image/png");
        assertThat(Base64.getDecoder().decode(data(preview).path("imageBase64").asText())).isNotEmpty();
        var scan = data(call("POST", "/payments/qr/scan", payer.token(), Map.of("qrString",
                data(call("GET", "/merchants/me/qr?currency=KHR", shop.merchant(), null)).path("qrString").asText())));
        assertThat(scan.path("merchant").path("hasLogo").asBoolean()).isTrue();
        jdbc.update("UPDATE merchants SET status='SUSPENDED' WHERE owner_user_id=?", shop.owner());
        assertThat(call("GET", "/payments/merchants/" + shop.code() + "/logo", payer.token(), null).statusCode()).isEqualTo(404);
    }

    // ---- fixtures ----

    Shop shop() throws Exception {
        record Tokens(long id, String merchant, String customer) {}
        var tokens = new TransactionTemplate(txManager).execute(s -> {
            var u = users.saveAndFlush(User.builder().username("m6.shop." + UUID.randomUUID()).firstName("Synthetic").lastName("Owner")
                    .profileComplete(true).enabled(true).roles(new HashSet<>(Set.of(roles.findByName(ERole.ROLE_CUSTOMER).orElseThrow()))).build());
            TokenResponseDto customer = sessions.create(u, devices.bind(u, UUID.randomUUID().toString(), "Customer fixture", "MOBILE", "Android", "127.0.0.1"));
            TokenResponseDto merchant = sessions.createMerchant(u, devices.bind(u, "merchant:" + UUID.randomUUID(), "Merchant fixture", "MOBILE", "Android", "127.0.0.1"));
            return new Tokens(u.getId(), merchant.getAccessToken(), customer.getAccessToken());
        });
        var registered = call("POST", "/merchants/me/registration", tokens.merchant(), Map.of("storeName", "Sokha Coffee",
                "categoryCode", "FOOD_DRINK", "phone", "012 345 678", "city", "Phnom Penh", "address", "St. 51"),
                Map.of("Idempotency-Key", key()));
        assertThat(registered.statusCode()).as(registered.body()).isEqualTo(201);
        var profile = data(registered);
        return new Shop(tokens.id(), tokens.merchant(), tokens.customer(), profile.path("shop").path("merchantId").asText(),
                profile.path("wallets").get(0).path("accountNumber").asText(), profile.path("wallets").get(1).path("accountNumber").asText());
    }

    Payer payer() throws Exception {
        record Opened(long id, String token, String usd, String khr) {}
        var opened = new TransactionTemplate(txManager).execute(s -> {
            var u = users.saveAndFlush(User.builder().username("m6.payer." + UUID.randomUUID()).firstName("Payer").lastName("Person")
                    .profileComplete(true).enabled(true).roles(new HashSet<>(Set.of(roles.findByName(ERole.ROLE_CUSTOMER).orElseThrow()))).build());
            var wallets = accounts.createDefaultUserWallets(u);
            TokenResponseDto session = sessions.create(u, devices.bind(u, UUID.randomUUID().toString(), "Payer fixture", "MOBILE", "Android", "127.0.0.1"));
            return new Opened(u.getId(), session.getAccessToken(), wallets.get(0).getAccountNumber(), wallets.get(1).getAccountNumber());
        });
        var prepared = call("POST", "/auth/pin/prepare", opened.token(), null);
        assertThat(prepared.statusCode()).as(prepared.body()).isEqualTo(200);
        var setup = call("POST", "/auth/pin/setup", null, Map.of("ticket", data(prepared).path("ticket").asText(), "pin", "0427", "confirmPin", "0427"));
        assertThat(setup.statusCode()).as(setup.body()).isEqualTo(200);
        return new Payer(opened.id(), data(setup).path("accessToken").asText(), opened.usd(), opened.khr());
    }

    HttpResponse<String> request(Shop shop, String key, Map<String, Object> body) throws Exception {
        return call("POST", "/merchants/me/payment-requests", shop.merchant(), body, Map.of("Idempotency-Key", key));
    }
    HttpResponse<String> pay(Payer payer, String source, String qr, String amount, String currency, String key) throws Exception {
        var body = new HashMap<String, Object>(Map.of("sourceAccountNumber", source, "qrString", qr, "currency", currency));
        if (amount != null) body.put("amount", amount);
        return call("POST", "/payments/qr/transfer", payer.token(), body, Map.of("Idempotency-Key", key));
    }
    BigDecimal balance(String number) {
        return jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number=?", BigDecimal.class, number);
    }
    long collectionsOf(Shop shop) {
        return jdbc.queryForObject("SELECT count(*) FROM merchant_collections c JOIN merchants m ON m.id=c.merchant_id WHERE m.owner_user_id=?",
                Long.class, shop.owner());
    }
    String key() { return UUID.randomUUID().toString(); }
    List<HttpResponse<String>> race(Callable<HttpResponse<String>> one, Callable<HttpResponse<String>> two) throws Exception {
        try (var pool = Executors.newFixedThreadPool(2)) {
            var start = new CountDownLatch(1);
            var a = pool.submit(() -> { start.await(); return one.call(); });
            var b = pool.submit(() -> { start.await(); return two.call(); });
            start.countDown(); return List.of(a.get(30, TimeUnit.SECONDS), b.get(30, TimeUnit.SECONDS));
        }
    }
    JsonNode data(HttpResponse<String> r) { return json.readTree(r.body()).path("data"); }
    String error(HttpResponse<String> r) { return json.readTree(r.body()).path("error").asText(); }
    HttpResponse<String> call(String method, String path, String token, Object body) throws Exception { return call(method, path, token, body, Map.of()); }
    HttpResponse<String> call(String method, String path, String token, Object body, Map<String, String> headers) throws Exception {
        var req = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/v1" + path)).timeout(Duration.ofSeconds(25));
        if (token != null) req.header("Authorization", "Bearer " + token);
        if (body != null) req.header("Content-Type", "application/json");
        headers.forEach(req::header);
        return http.send(req.method(method, body == null ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body))).build(), HttpResponse.BodyHandlers.ofString());
    }
}
