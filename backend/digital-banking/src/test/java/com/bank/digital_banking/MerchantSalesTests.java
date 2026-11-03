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

/** M7 HTTP contracts against isolated PostgreSQL; uses the M6 shop/payer/payment fixtures. */
@SpringBootTest(classes = DigitalBankingApplication.class, webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "app.dev.opening-funding.enabled=true")
class MerchantSalesTests extends PostgresIntegrationTest {
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

    @Test void requestHistoryBoundsExpiryWorkAndPagesEveryEffectivelyExpiredRequest() throws Exception {
        var shop = shop();
        var active = data(request(shop, key(), Map.of("currency", "USD", "amount", "1.00")));
        int inserted = jdbc.update("""
                WITH batch AS (
                    INSERT INTO payments(md5_hash,account_number,amount,currency,status,qr_type)
                    SELECT md5(random()::text || g::text),?,1,'USD','PENDING','DYNAMIC'
                    FROM generate_series(1,160) g RETURNING id
                )
                INSERT INTO merchant_payment_requests(id,merchant_id,owner_user_id,payment_id,account_number,
                    currency,amount,reference,key_hash,request_hash,created_at,expires_at)
                SELECT gen_random_uuid(),(SELECT id FROM merchants WHERE owner_user_id=?),?,id,?,
                    'USD',1,'F4-' || id,md5(id::text)||md5('key-'||id::text),repeat('a',64),
                    now()-interval '2 hours',now()-interval '1 hour' FROM batch
                """, shop.usd(), shop.owner(), shop.owner(), shop.usd());
        assertThat(inserted).isEqualTo(160);
        var waiting = call("GET", "/merchants/me/payment-requests?status=WAITING&size=50", shop.merchant(), null);
        assertThat(waiting.statusCode()).as(waiting.body()).isEqualTo(200);
        assertThat(data(waiting).path("items")).hasSize(1);
        assertThat(data(waiting).path("items").get(0).path("requestId").asText()).isEqualTo(active.path("requestId").asText());
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_payment_requests WHERE owner_user_id=? AND status='EXPIRED'",
                Long.class, shop.owner())).isEqualTo(50);

        // An unfiltered page must settle its due rows too, within the same cap.
        var all = data(call("GET", "/merchants/me/payment-requests?size=50", shop.merchant(), null));
        assertThat(all.path("items")).hasSize(50);
        for (var item : all.path("items")) {
            if (!item.path("requestId").asText().equals(active.path("requestId").asText()))
                assertThat(item.path("status").asText()).isEqualTo("EXPIRED");
        }
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_payment_requests WHERE owner_user_id=? AND status='EXPIRED'",
                Long.class, shop.owner())).isEqualTo(100);

        var seen = new HashSet<String>(); String cursor = null;
        do {
            var response = call("GET", "/merchants/me/payment-requests?status=EXPIRED&size=20" + (cursor == null ? "" : "&cursor=" + cursor), shop.merchant(), null);
            assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
            var page = data(response);
            for (var item : page.path("items")) {
                assertThat(item.path("status").asText()).isEqualTo("EXPIRED");
                assertThat(seen.add(item.path("requestId").asText())).isTrue();
                assertThat(item.has("qrString")).isFalse();
            }
            cursor = page.path("nextCursor").isNull() ? null : page.path("nextCursor").asText();
        } while (cursor != null);
        assertThat(seen).hasSize(160);
        assertThat(data(call("GET", "/merchants/me/payment-requests?status=WAITING", shop.merchant(), null)).path("items")).hasSize(1);
    }

    JsonNode sale(Shop shop, Payer payer, String currency, String amount, String order) throws Exception {
        var r = data(request(shop, key(), Map.of("currency", currency, "amount", amount, "orderReference", order)));
        var paid = pay(payer, currency.equals("USD") ? payer.usd() : payer.khr(), r.path("qrString").asText(), null, currency, key());
        assertThat(paid.statusCode()).as(paid.body()).isEqualTo(200);
        return data(call("GET", "/merchants/me/payment-requests/" + r.path("requestId").asText(), shop.merchant(), null)).path("receipt");
    }
    JsonNode sales(Shop shop, String query) throws Exception {
        var response = call("GET", "/merchants/me/sales" + query, shop.merchant(), null);
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        assertThat(response.headers().firstValue("Cache-Control").orElse("")).contains("no-store");
        return data(response);
    }
    void time(String reference, String at) {
        jdbc.update("UPDATE merchant_collections SET created_at=?::timestamptz WHERE reference_number=?", at, reference);
    }
    @Test void keysetPagesRemainStableWhenANewPaymentArrives() throws Exception {
        var shop = shop(); var payer = payer();
        var expected = new HashSet<String>();
        for (int i=0;i<7;i++) expected.add(sale(shop,payer,"USD","1.00","Page").path("reference").asText());
        // Equal timestamps exercise transaction_id as the required tiebreaker.
        jdbc.update("UPDATE merchant_collections SET created_at=date_trunc('day',now() AT TIME ZONE 'Asia/Phnom_Penh') AT TIME ZONE 'Asia/Phnom_Penh' WHERE merchant_id=(SELECT id FROM merchants WHERE owner_user_id=?)",shop.owner());
        var first=sales(shop,"?size=2");
        var seen=new ArrayList<String>(); first.path("items").forEach(r->seen.add(r.path("reference").asText()));
        sale(shop,payer,"USD","1.00","Arriving");
        String cursor=first.path("nextCursor").asText();
        while(cursor!=null) {
            var page=sales(shop,"?size=2&cursor="+cursor);
            page.path("items").forEach(r->seen.add(r.path("reference").asText()));
            cursor=page.path("nextCursor").isNull()?null:page.path("nextCursor").asText();
        }
        assertThat(seen).hasSize(7).doesNotHaveDuplicates().containsExactlyInAnyOrderElementsOf(expected);
    }
    @Test void filtersMatchCurrencyBusinessDatesOrderAndRequestAndReferenceSuffix() throws Exception {
        var shop=shop(); var payer=payer();
        var usd=sale(shop,payer,"USD","2.50","TableBlue"); sale(shop,payer,"KHR","1000","Other");
        assertThat(sales(shop,"?currency=USD").path("items")).hasSize(1);
        assertThat(sales(shop,"?q=tableblue").path("items").get(0).path("reference").asText()).isEqualTo(usd.path("reference").asText());
        assertThat(sales(shop,"?q="+usd.path("requestReference").asText().toLowerCase()).path("items")).hasSize(1);
        String ref=usd.path("reference").asText();
        assertThat(sales(shop,"?q="+ref.substring(ref.length()-8)).path("items")).hasSize(1);
        assertThat(sales(shop,"?q=%25").path("items")).isEmpty();
        time(ref,"2026-02-01T12:00:00+07:00");
        assertThat(sales(shop,"?from=2026-02-01&to=2026-02-01&currency=USD").path("items")).hasSize(1);
    }
    @Test void totalsCoverWholeFilterRatherThanPage() throws Exception {
        var shop=shop(); var payer=payer();
        for(int i=0;i<3;i++) sale(shop,payer,"USD","1.25","Total");
        sale(shop,payer,"KHR","500","Total");
        var list=sales(shop,"?size=1"); assertThat(list.path("items")).hasSize(1);
        assertThat(list.path("totals").get(0).path("gross").asText()).isEqualTo("500");
        assertThat(list.path("totals").get(1).path("gross").asText()).isEqualTo("3.75");
        assertThat(list.path("totals").get(1).path("count").asInt()).isEqualTo(3);
        assertThat(sales(shop,"?currency=KHR").path("totals").get(1).path("gross").asText()).isEqualTo("0.00");
    }
    @Test void phnomPenhMidnightSplitsBusinessDays() throws Exception {
        var shop=shop(); var payer=payer();
        time(sale(shop,payer,"USD","2.00","Before").path("reference").asText(),"2026-05-01T23:59:00+07:00");
        time(sale(shop,payer,"USD","3.00","After").path("reference").asText(),"2026-05-02T00:01:00+07:00");
        assertThat(sales(shop,"?from=2026-05-01&to=2026-05-01").path("totals").get(1).path("gross").asText()).isEqualTo("2.00");
        assertThat(sales(shop,"?from=2026-05-02&to=2026-05-02").path("totals").get(1).path("gross").asText()).isEqualTo("3.00");
    }
    @Test void dailyAndMonthlyReportsZeroFillAndReconcileBothCurrencies() throws Exception {
        var shop=shop(); var payer=payer();
        time(sale(shop,payer,"USD","2.25","Report").path("reference").asText(),"2026-02-01T23:59:00+07:00");
        time(sale(shop,payer,"KHR","700","Report").path("reference").asText(),"2026-03-01T00:01:00+07:00");
        for(String period:List.of("DAY","MONTH")) {
            var r=call("GET","/merchants/me/reports/collections?period="+period+"&from=2026-02-01&to=2026-04-01",shop.merchant(),null);
            assertThat(r.statusCode()).as(r.body()).isEqualTo(200);
            var report=data(r);
            assertThat(report.path("buckets")).hasSize(period.equals("DAY")?120:6);
            assertThat(report.path("totals")).isEqualTo(sales(shop,"?from=2026-02-01&to=2026-04-01").path("totals"));
            assertThat(report.path("buckets").get(report.path("buckets").size()-1).path("gross").asText()).isEqualTo("0.00");
        }
    }
    @Test void nonCollectionActivityAndUnpaidRequestsAreExcludedAndHistorySettlesExpiry() throws Exception {
        var shop=shop(); var payer=payer();
        var kept=sale(shop,payer,"USD","1.00","Only sale");
        // Fixture ledger activity: real non-QR types, no merchant_collections row.
        for(String type:List.of("DEPOSIT","TRANSFER")) jdbc.update("INSERT INTO transactions(reference_number,source_account_id,destination_account_id,amount,fee,currency,transaction_type,status) SELECT ?,?,id,5,0,'USD',?,'SUCCESS' FROM accounts WHERE account_number=?",UUID.randomUUID().toString(),type.equals("DEPOSIT")?null:jdbc.queryForObject("SELECT id FROM accounts WHERE account_number=?",Long.class,payer.usd()),type,shop.usd());
        var cancelled=data(request(shop,key(),Map.of("currency","USD","amount","1.00")));
        call("POST","/merchants/me/payment-requests/"+cancelled.path("requestId").asText()+"/cancel",shop.merchant(),null);
        var expired=data(request(shop,key(),Map.of("currency","USD","amount","1.00")));
        jdbc.update("UPDATE merchant_payment_requests SET created_at=now()-interval '1 hour',expires_at=now()-interval '1 second' WHERE id=?",UUID.fromString(expired.path("requestId").asText()));
        var history=data(call("GET","/merchants/me/payment-requests?status=EXPIRED",shop.merchant(),null));
        assertThat(history.path("items")).hasSize(1);
        assertThat(history.path("items").get(0).has("qrString")).isFalse();
        var all=data(call("GET","/merchants/me/payment-requests?size=1",shop.merchant(),null));
        assertThat(all.path("items")).hasSize(1); assertThat(all.path("nextCursor").isNull()).isFalse();
        var next=data(call("GET","/merchants/me/payment-requests?size=1&cursor="+all.path("nextCursor").asText(),shop.merchant(),null));
        assertThat(next.path("items").get(0).path("requestId")).isNotEqualTo(all.path("items").get(0).path("requestId"));
        assertThat(sales(shop,"").path("items")).hasSize(1);
        var report=data(call("GET","/merchants/me/reports/collections",shop.merchant(),null));
        assertThat(report.path("totals").get(1).path("gross").asText()).isEqualTo("1.00");
        assertThat(data(call("GET","/merchants/me/wallets/"+shop.usd(),shop.merchant(),null)).path("activity")).hasSize(3);
    }
    @Test void foreignReceiptsPurposeAndMalformedFiltersFailClosed() throws Exception {
        var shop=shop(); var other=shop(); var payer=payer();
        var receipt=sale(shop,payer,"USD","1.00","Private");
        assertThat(call("GET","/merchants/me/sales/"+receipt.path("reference").asText(),other.merchant(),null).statusCode()).isEqualTo(404);
        for(String path:List.of("/sales","/sales/"+receipt.path("reference").asText(),"/reports/collections","/payment-requests"))
            assertThat(error(call("GET","/merchants/me"+path,shop.customer(),null))).isEqualTo("MERCHANT_SESSION_REQUIRED");
        for(String query:List.of("?cursor=bad","?cursor=","?from=2026-02-30","?from=2025-01-01&to=2026-01-02","?from=2026-11-02&to=2026-11-01","?size=51","?size=0","?currency=EUR","?q=","?q="+"x".repeat(51)))
            assertThat(call("GET","/merchants/me/sales"+query,shop.merchant(),null).statusCode()).as(query).isEqualTo(400);
        for(String query:List.of("?period=YEAR","?period=DAY&from=2026-01-01&to=2026-04-03","?period=MONTH&from=2024-01-01&to=2026-01-01"))
            assertThat(call("GET","/merchants/me/reports/collections"+query,shop.merchant(),null).statusCode()).isEqualTo(400);
        assertThat(call("GET","/merchants/me/payment-requests?status=BAD",shop.merchant(),null).statusCode()).isEqualTo(400);
        assertThat(sales(other,"").path("items")).isEmpty();
        jdbc.update("UPDATE merchants SET status='SUSPENDED' WHERE owner_user_id=?",shop.owner());
        assertThat(sales(shop,"").path("items")).hasSize(1);
    }
    @Test void receiptKeepsPaymentTimeShopIdentityAndExactConversion() throws Exception {
        var shop=shop(); var payer=payer();
        var r=data(request(shop,key(),Map.of("currency","KHR","amount","10000","orderReference","Table 4")));
        assertThat(pay(payer,payer.usd(),r.path("qrString").asText(),null,"USD",key()).statusCode()).isEqualTo(200);
        var ref=data(call("GET","/merchants/me/payment-requests/"+r.path("requestId").asText(),shop.merchant(),null)).path("receipt").path("reference").asText();
        assertThat(call("PATCH","/merchants/me/profile",shop.merchant(),Map.of("version",0,"storeName","New Name")).statusCode()).isEqualTo(200);
        var receipt=data(call("GET","/merchants/me/sales/"+ref,shop.merchant(),null));
        assertThat(receipt.path("storeName").asText()).isEqualTo("Sokha Coffee");
        assertThat(receipt.path("amount").asText()).isEqualTo("10000");
        assertThat(receipt.path("paidAmount").asText()).isEqualTo("2.50");
        assertThat(receipt.path("exchangeRate").asText()).isEqualTo("4000.0000");
        assertThat(receipt.path("walletAccountNumber").asText()).isEqualTo(shop.khr());
        assertThat(receipt.path("payerAccount").asText()).startsWith("•••• ");
        assertThat(receipt.toString()).doesNotContain(payer.usd(),"Person","Synthetic Owner");
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
