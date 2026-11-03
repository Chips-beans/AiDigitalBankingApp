package com.bank.digital_banking;

import com.bank.digital_banking.module.auth.dto.TokenResponseDto;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.service.*;
import com.bank.digital_banking.module.merchant.service.MerchantOnboardingPolicy;
import com.bank.digital_banking.module.merchant.service.MerchantShopService;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.*;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import static org.assertj.core.api.Assertions.*;

/** M4 shop onboarding over HTTP, with customer development funding enabled to prove merchant wallets stay at zero. */
@SpringBootTest(classes = DigitalBankingApplication.class, webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "app.dev.opening-funding.enabled=true")
class MerchantShopTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired UserRepository users;
    @Autowired RoleRepository roles;
    @Autowired SessionService sessions;
    @Autowired DeviceService devices;
    @Autowired PlatformTransactionManager txManager;
    @Autowired MerchantShopService shopService;
    final HttpClient http = HttpClient.newHttpClient();
    record Owner(long id, String merchant, String customer) {}

    @BeforeEach void limits() { jdbc.update("DELETE FROM merchant_auth_limits"); }

    @Test void registrationCreatesOneActiveShopAndTwoZeroWalletsWithoutTouchingPersonalData() throws Exception {
        var o = owner();
        assertThat(state(o)).isEqualTo("SHOP_REQUIRED");
        long postings = jdbc.queryForObject("SELECT count(*) FROM transactions", Long.class);
        var r = register(o, key(), shopBody());
        assertThat(r.statusCode()).as(r.body()).isEqualTo(201);
        assertThat(r.headers().firstValue("Cache-Control").orElse("")).contains("no-store");
        var p = data(r);
        assertThat(p.path("onboardingState").asText()).isEqualTo("READY");
        assertThat(p.path("owner").path("id").asLong()).isEqualTo(o.id());
        var shop = p.path("shop");
        assertThat(shop.path("merchantId").asText()).matches("MCH-[A-Z2-9]{8}");
        assertThat(shop.path("storeName").asText()).isEqualTo("Sokha Coffee");
        assertThat(shop.path("categoryCode").asText()).isEqualTo("FOOD_DRINK");
        assertThat(shop.path("phone").asText()).isEqualTo("+85512345678");
        assertThat(shop.path("status").asText()).isEqualTo("ACTIVE");
        assertThat(shop.path("version").asLong()).isZero();
        var wallets = p.path("wallets");
        assertThat(wallets).hasSize(2);
        assertThat(wallets.get(0).path("currency").asText()).isEqualTo("KHR");
        assertThat(wallets.get(0).path("balance").asText()).isEqualTo("0");
        assertThat(wallets.get(1).path("currency").asText()).isEqualTo("USD");
        assertThat(wallets.get(1).path("balance").asText()).isEqualTo("0.00");
        assertThat(wallets.get(0).path("accountNumber").asText()).isNotEqualTo(wallets.get(1).path("accountNumber").asText());
        for (var w : wallets) {
            assertThat(w.path("category").asText()).isEqualTo("MERCHANT");
            assertThat(w.path("merchantId").asText()).isEqualTo(shop.path("merchantId").asText());
        }
        // Customer development funding is enabled, but merchant wallets receive no opening credit.
        assertThat(jdbc.queryForObject("SELECT count(*) FROM transactions", Long.class)).isEqualTo(postings);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM accounts WHERE user_id=? AND account_category='WALLET'", Long.class, o.id())).isZero();
        assertThat(jdbc.queryForObject("SELECT first_name FROM users WHERE id=?", String.class, o.id())).isEqualTo("Synthetic");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=? AND r.name='ROLE_MERCHANT'",
                Long.class, o.id())).isZero();
        var identity = data(call("GET", "/merchant-auth/session", o.merchant(), null));
        assertThat(identity.path("onboardingState").asText()).isEqualTo("READY");
        assertThat(identity.path("shop").path("merchantId").asText()).isEqualTo(shop.path("merchantId").asText());
        assertThat(String.join(" ", jdbc.queryForList("SELECT coalesce(action,'') FROM audit_logs WHERE module_name='MERCHANT' AND target_resource_id=?",
                String.class, shop.path("merchantId").asText()))).contains("SHOP_REGISTERED");
    }

    @Test void sameKeyReplaysChangedBodyConflictsAndSecondShopIsRejected() throws Exception {
        var o = owner(); String key = key();
        var first = register(o, key, shopBody());
        assertThat(first.statusCode()).isEqualTo(201);
        var replay = register(o, key, shopBody());
        assertThat(replay.statusCode()).as(replay.body()).isEqualTo(200);
        assertThat(data(replay).path("shop").path("merchantId").asText()).isEqualTo(data(first).path("shop").path("merchantId").asText());
        var changed = shopBody(); changed.put("storeName", "Another Shop");
        assertThat(error(register(o, key, changed))).isEqualTo("MERCHANT_REGISTRATION_CONFLICT");
        assertThat(error(register(o, key(), changed))).isEqualTo("MERCHANT_ALREADY_REGISTERED");
        assertCounts(o, 1, 2);
    }

    @Test void concurrentRegistrationsCreateExactlyOneShop() throws Exception {
        var o = owner();
        var different = race(() -> register(o, key(), shopBody()), () -> register(o, key(), shopBody()));
        assertThat(different.stream().map(HttpResponse::statusCode)).containsExactlyInAnyOrder(201, 409);
        assertCounts(o, 1, 2);
        var same = owner(); String key = key();
        var replayed = race(() -> register(same, key, shopBody()), () -> register(same, key, shopBody()));
        assertThat(replayed.stream().map(HttpResponse::statusCode)).containsExactlyInAnyOrder(201, 200);
        assertThat(data(replayed.get(0)).path("shop").path("merchantId").asText())
                .isEqualTo(data(replayed.get(1)).path("shop").path("merchantId").asText());
        assertCounts(same, 1, 2);
    }

    @Test void secondWalletFailureRollsBackShopFirstWalletLogoAndJournal() throws Exception {
        var o = owner(); String key = key();
        String logo = data(upload(o, png(300, 200))).path("logoId").asText();
        var body = shopBody(); body.put("stagedLogoId", logo);
        jdbc.execute("ALTER TABLE accounts ADD CONSTRAINT qa_reject_merchant_usd CHECK(account_category <> 'MERCHANT' OR currency <> 'USD') NOT VALID");
        try {
            assertThat(register(o, key, body).statusCode()).isGreaterThanOrEqualTo(400);
            assertCounts(o, 0, 0);
            assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_registration_requests WHERE owner_user_id=?", Long.class, o.id())).isZero();
            assertThat(jdbc.queryForObject("SELECT status FROM merchant_logos WHERE id=?::uuid", String.class, logo)).isEqualTo("STAGED");
        } finally { jdbc.execute("ALTER TABLE accounts DROP CONSTRAINT qa_reject_merchant_usd"); }
        // The same intent can be retried explicitly after the failure.
        var retried = register(o, key, body);
        assertThat(retried.statusCode()).as(retried.body()).isEqualTo(201);
        assertThat(data(retried).path("shop").path("logoId").asText()).isEqualTo(logo);
        assertCounts(o, 1, 2);
    }

    @Test void clientControlledFieldsAndInvalidValuesAreRejected() throws Exception {
        var o = owner();
        for (var field : List.of("ownerUserId", "merchantId", "status", "openingBalance", "bakongAccountId", "merchantAccountId")) {
            var body = shopBody(); body.put(field, field.equals("ownerUserId") ? 1 : "ACTIVE");
            var r = register(o, key(), body);
            assertThat(r.statusCode()).as(field).isEqualTo(400);
        }
        var badCategory = shopBody(); badCategory.put("categoryCode", "CASINO");
        assertThat(error(register(o, key(), badCategory))).isEqualTo("MERCHANT_CATEGORY_INVALID");
        for (String phone : List.of("12", "+855012345678", "phone", "+85512")) {
            var badPhone = shopBody(); badPhone.put("phone", phone);
            assertThat(error(register(o, key(), badPhone))).as(phone).isEqualTo("MERCHANT_PHONE_INVALID");
        }
        var blank = shopBody(); blank.put("storeName", "   ");
        assertThat(error(register(o, key(), blank))).isEqualTo("VALIDATION_FAILED");
        var control = shopBody(); control.put("city", "Phnom\u0000Penh");
        assertThat(register(o, key(), control).statusCode()).isEqualTo(400);
        assertThat(error(call("POST", "/merchants/me/registration", o.merchant(), shopBody()))).isEqualTo("IDEMPOTENCY_KEY_REQUIRED");
        assertThat(error(register(o, "short", shopBody()))).isEqualTo("IDEMPOTENCY_KEY_REQUIRED");
        assertCounts(o, 0, 0);
    }

    @Test void shopApisRequireMerchantPurposeAndMerchantSessionsCannotUsePersonalApis() throws Exception {
        var o = owner();
        assertThat(call("GET", "/merchants/me", null, null).statusCode()).isEqualTo(401);
        assertThat(error(call("GET", "/merchants/me", o.customer(), null))).isEqualTo("MERCHANT_SESSION_REQUIRED");
        assertThat(error(call("POST", "/merchants/me/registration", o.customer(), shopBody(), Map.of("Idempotency-Key", key()))))
                .isEqualTo("MERCHANT_SESSION_REQUIRED");
        assertThat(error(call("GET", "/accounts", o.merchant(), null))).isEqualTo("CUSTOMER_SESSION_REQUIRED");
        assertThat(error(call("GET", "/merchants/1", o.merchant(), null))).isEqualTo("CUSTOMER_SESSION_REQUIRED");
        jdbc.update("UPDATE auth_sessions SET revoked_at=CURRENT_TIMESTAMP WHERE user_id=? AND purpose='MERCHANT'", o.id());
        assertThat(call("GET", "/merchants/me", o.merchant(), null).statusCode()).isEqualTo(401);
        assertCounts(o, 0, 0);
    }

    @Test void logoUploadsAreNormalizedOwnerScopedAndAttachedOnlyWhenValid() throws Exception {
        var o = owner(); var other = owner();
        var staged = upload(o, png(2000, 1000));
        assertThat(staged.statusCode()).as(staged.body()).isEqualTo(201);
        assertThat(data(staged).path("width").asInt()).isEqualTo(512);
        assertThat(data(staged).path("height").asInt()).isEqualTo(256);
        assertThat(error(upload(o, "not an image".getBytes()))).isEqualTo("MERCHANT_LOGO_INVALID");
        String foreign = data(upload(other, png(64, 64))).path("logoId").asText();
        var stolen = shopBody(); stolen.put("stagedLogoId", foreign);
        assertThat(error(register(o, key(), stolen))).isEqualTo("MERCHANT_LOGO_INVALID");
        var unknown = shopBody(); unknown.put("stagedLogoId", UUID.randomUUID().toString());
        assertThat(error(register(o, key(), unknown))).isEqualTo("MERCHANT_LOGO_INVALID");
        assertCounts(o, 0, 0);

        var body = shopBody(); body.put("stagedLogoId", data(staged).path("logoId").asText());
        var shop = data(register(o, key(), body)).path("shop");
        assertThat(shop.path("logoId").asText()).isEqualTo(data(staged).path("logoId").asText());
        var image = http.send(HttpRequest.newBuilder(uri("/merchants/me/logo")).header("Authorization", "Bearer " + o.merchant()).build(),
                HttpResponse.BodyHandlers.ofByteArray());
        assertThat(image.statusCode()).isEqualTo(200);
        assertThat(image.headers().firstValue("Content-Type").orElse("")).startsWith("image/png");
        assertThat(ImageIO.read(new java.io.ByteArrayInputStream(image.body())).getWidth()).isEqualTo(512);
        assertThat(http.send(HttpRequest.newBuilder(uri("/merchants/me/logo")).header("Authorization", "Bearer " + other.merchant()).build(),
                HttpResponse.BodyHandlers.ofString()).statusCode()).isEqualTo(404);
        // An attached logo cannot be re-attached by anyone, and the personal profile photo is untouched.
        var reuse = Map.<String, Object>of("version", 0, "stagedLogoId", foreign);
        assertThat(error(call("PATCH", "/merchants/me/profile", o.merchant(), reuse))).isEqualTo("MERCHANT_LOGO_INVALID");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM customer_profile_photos WHERE user_id=?", Long.class, o.id())).isZero();
    }

    @Test void profileEditsUseVersionsAndRespectShopStatus() throws Exception {
        var o = owner();
        String logo = data(upload(o, png(80, 80))).path("logoId").asText();
        var body = shopBody(); body.put("stagedLogoId", logo);
        assertThat(register(o, key(), body).statusCode()).isEqualTo(201);
        var edited = call("PATCH", "/merchants/me/profile", o.merchant(),
                Map.of("version", 0, "storeName", "  Sokha   Coffee 2 ", "categoryCode", "retail", "description", ""));
        assertThat(edited.statusCode()).as(edited.body()).isEqualTo(200);
        var shop = data(edited).path("shop");
        assertThat(shop.path("storeName").asText()).isEqualTo("Sokha Coffee 2");
        assertThat(shop.path("categoryCode").asText()).isEqualTo("RETAIL");
        assertThat(shop.path("description").isNull()).isTrue();
        assertThat(shop.path("version").asLong()).isEqualTo(1);
        assertThat(error(call("PATCH", "/merchants/me/profile", o.merchant(), Map.of("version", 0, "city", "Siem Reap"))))
                .isEqualTo("MERCHANT_PROFILE_CONFLICT");
        assertThat(call("PATCH", "/merchants/me/profile", o.merchant(), Map.of("version", 1, "status", "ACTIVE")).statusCode()).isEqualTo(400);
        var removed = data(call("PATCH", "/merchants/me/profile", o.merchant(), Map.of("version", 1, "removeLogo", true)));
        assertThat(removed.path("shop").path("logoId").isNull()).isTrue();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_logos WHERE id=?::uuid", Long.class, logo)).isZero();
        assertThat(jdbc.queryForObject("SELECT first_name FROM users WHERE id=?", String.class, o.id())).isEqualTo("Synthetic");

        jdbc.update("UPDATE merchants SET status='SUSPENDED' WHERE owner_user_id=?", o.id());
        assertThat(data(call("GET", "/merchants/me", o.merchant(), null)).path("onboardingState").asText()).isEqualTo("RESTRICTED");
        assertThat(error(call("PATCH", "/merchants/me/profile", o.merchant(), Map.of("version", 2, "city", "Kampot"))))
                .isEqualTo("MERCHANT_INACTIVE");
    }

    @Test void legacyMultiShopOwnersNeedRecoveryAndAreNeverCollapsed() throws Exception {
        var o = owner();
        for (int i = 0; i < 2; i++) {
            String id = "LEGACY-" + UUID.randomUUID();
            jdbc.update("INSERT INTO merchants(merchant_id,store_name,bakong_account_id,merchant_city,status,owner_user_id) VALUES (?,?,?,'Phnom Penh','ACTIVE',?)",
                    id, "Legacy " + i, id + "@legacy", o.id());
        }
        var profile = data(call("GET", "/merchants/me", o.merchant(), null));
        assertThat(profile.path("onboardingState").asText()).isEqualTo("RECOVERY_REQUIRED");
        assertThat(profile.path("shop").isNull()).isTrue();
        assertThat(error(register(o, key(), shopBody()))).isEqualTo("MERCHANT_ALREADY_REGISTERED");
        assertThat(error(call("PATCH", "/merchants/me/profile", o.merchant(), Map.of("version", 0, "city", "Kep"))))
                .isEqualTo("MERCHANT_RECOVERY_REQUIRED");
        assertThat(jdbc.queryForList("SELECT merchant_city FROM merchants WHERE owner_user_id=?", String.class, o.id()))
                .containsOnly("Phnom Penh");
        assertCounts(o, 2, 0);
    }

    @Test void stagedLogosAreCappedPerOwnerAndSweptAfterRetention() throws Exception {
        var o = owner();
        for (int i = 0; i < 7; i++) assertThat(upload(o, png(10 + i, 10)).statusCode()).isEqualTo(201);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_logos WHERE owner_user_id=?", Long.class, o.id())).isEqualTo(5);
        jdbc.update("UPDATE merchant_logos SET created_at=CURRENT_TIMESTAMP-INTERVAL '2 days' WHERE owner_user_id=?", o.id());
        shopService.sweepStagedLogos();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_logos WHERE owner_user_id=?", Long.class, o.id())).isZero();
    }

    @Test void selfServiceActivationIsLimitedToDevelopmentProfiles() {
        for (String[] profiles : List.of(new String[]{"prod"}, new String[]{"staging"}, new String[]{"dev", "production"})) {
            var env = new MockEnvironment(); env.setActiveProfiles(profiles);
            assertThatThrownBy(() -> new MerchantOnboardingPolicy(env, true)).isInstanceOf(IllegalStateException.class);
            assertThat(new MerchantOnboardingPolicy(env, null).initialStatus()).isEqualTo("PENDING");
        }
        var env = new MockEnvironment(); env.setActiveProfiles("local", "test");
        assertThat(new MerchantOnboardingPolicy(env, null).initialStatus()).isEqualTo("ACTIVE");
        assertThat(new MerchantOnboardingPolicy(env, false).initialStatus()).isEqualTo("PENDING");
    }

    Owner owner() throws Exception {
        var tokens = new TransactionTemplate(txManager).execute(s -> {
            var u = users.saveAndFlush(User.builder().username("m4." + UUID.randomUUID()).firstName("Synthetic").lastName("Owner")
                    .profileComplete(true).enabled(true).roles(new HashSet<>(Set.of(roles.findByName(ERole.ROLE_CUSTOMER).orElseThrow()))).build());
            TokenResponseDto customer = sessions.create(u, devices.bind(u, UUID.randomUUID().toString(), "Customer fixture", "MOBILE", "Android", "127.0.0.1"));
            TokenResponseDto merchant = sessions.createMerchant(u, devices.bind(u, "merchant:" + UUID.randomUUID(), "Merchant fixture", "MOBILE", "Android", "127.0.0.1"));
            return new Owner(u.getId(), merchant.getAccessToken(), customer.getAccessToken());
        });
        return tokens;
    }
    Map<String, Object> shopBody() {
        return new HashMap<>(Map.of("storeName", "Sokha Coffee", "categoryCode", "FOOD_DRINK", "phone", "012 345 678",
                "city", "Phnom Penh", "address", "St. 51, Daun Penh", "description", "Coffee and pastries"));
    }
    String key() { return UUID.randomUUID().toString(); }
    HttpResponse<String> register(Owner o, String key, Map<String, Object> body) throws Exception {
        return call("POST", "/merchants/me/registration", o.merchant(), body, Map.of("Idempotency-Key", key));
    }
    String state(Owner o) throws Exception { return data(call("GET", "/merchants/me", o.merchant(), null)).path("onboardingState").asText(); }
    void assertCounts(Owner o, long shops, long wallets) {
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchants WHERE owner_user_id=?", Long.class, o.id())).isEqualTo(shops);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM accounts WHERE user_id=? AND account_category='MERCHANT'", Long.class, o.id())).isEqualTo(wallets);
    }
    byte[] png(int w, int h) throws Exception {
        var image = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
        var out = new ByteArrayOutputStream(); ImageIO.write(image, "png", out); return out.toByteArray();
    }
    HttpResponse<String> upload(Owner o, byte[] bytes) throws Exception {
        String boundary = "m4" + UUID.randomUUID().toString().replace("-", "");
        var out = new ByteArrayOutputStream();
        out.write(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"logo\"; filename=\"logo.png\"\r\n"
                + "Content-Type: image/png\r\n\r\n").getBytes());
        out.write(bytes);
        out.write(("\r\n--" + boundary + "--\r\n").getBytes());
        return http.send(HttpRequest.newBuilder(uri("/merchants/me/logo-uploads")).timeout(Duration.ofSeconds(25))
                .header("Authorization", "Bearer " + o.merchant()).header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .POST(HttpRequest.BodyPublishers.ofByteArray(out.toByteArray())).build(), HttpResponse.BodyHandlers.ofString());
    }
    List<HttpResponse<String>> race(Callable<HttpResponse<String>> one, Callable<HttpResponse<String>> two) throws Exception {
        try (var pool = Executors.newFixedThreadPool(2)) {
            var start = new CountDownLatch(1);
            var a = pool.submit(() -> { start.await(); return one.call(); });
            var b = pool.submit(() -> { start.await(); return two.call(); });
            start.countDown(); return List.of(a.get(30, TimeUnit.SECONDS), b.get(30, TimeUnit.SECONDS));
        }
    }
    URI uri(String path) { return URI.create("http://localhost:" + port + "/api/v1" + path); }
    JsonNode data(HttpResponse<String> r) { return json.readTree(r.body()).path("data"); }
    String error(HttpResponse<String> r) { return json.readTree(r.body()).path("error").asText(); }
    HttpResponse<String> call(String method, String path, String token, Object body) throws Exception { return call(method, path, token, body, Map.of()); }
    HttpResponse<String> call(String method, String path, String token, Object body, Map<String, String> headers) throws Exception {
        var req = HttpRequest.newBuilder(uri(path)).timeout(Duration.ofSeconds(25));
        if (token != null) req.header("Authorization", "Bearer " + token);
        if (body != null) req.header("Content-Type", "application/json");
        headers.forEach(req::header);
        return http.send(req.method(method, body == null ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body))).build(), HttpResponse.BodyHandlers.ofString());
    }
}
