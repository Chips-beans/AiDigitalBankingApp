package com.bank.digital_banking;

import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.transaction.entity.*;
import com.bank.digital_banking.module.transaction.repository.TransactionRepository;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import tools.jackson.databind.*;
import java.math.BigDecimal;
import java.net.URI;
import java.net.http.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import static org.assertj.core.api.Assertions.*;

class PhaseZeroIntegrationTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired UserRepository users;
    @Autowired DeviceRepository devices;
    @Autowired OtpRepository otps;
    @Autowired OtpRateLimitRepository limits;
    @Autowired AuthSessionRepository sessions;
    @Autowired AccountRepository accounts;
    @Autowired TransactionRepository transactions;
    @Autowired com.bank.digital_banking.module.payment.repository.PaymentRepository payments;
    final HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    @BeforeEach void reset() {
        sessions.deleteAll();
        otps.deleteAll();
        limits.deleteAll();
        users.findAll().forEach(u -> { u.setEnabled(true); users.save(u); });
        devices.findAll().forEach(d -> { d.setStatus(DeviceStatus.ACTIVE); devices.save(d); });
        SMTP.reset();
    }

    @Test void protectedRequestsRequireRealAccessTokens() throws Exception {
        var absent = call("GET", "/accounts/me", null, null);
        assertThat(absent.statusCode()).isEqualTo(401);
        assertThat(body(absent).path("error").asText()).isEqualTo("AUTHENTICATION_REQUIRED");
        assertThat(body(absent).path("success").asBoolean()).isFalse();
        assertThat(call("GET", "/accounts/me", "broken.jwt", null).statusCode()).isEqualTo(401);
        JsonNode login = login("alice.demo", "protected-device");
        assertThat(call("GET", "/accounts/me", login.path("refreshToken").asText(), null).statusCode()).isEqualTo(401);
        String expired = Jwts.builder().issuer("digital-banking").subject(login.path("userId").asText())
                .claim("type", "access").claim("sid", login.path("sessionId").asText()).id(UUID.randomUUID().toString())
                .issuedAt(new Date(0)).expiration(new Date(1))
                .signWith(Keys.hmacShaKeyFor(Decoders.BASE64.decode(SECRET)), Jwts.SIG.HS256).compact();
        assertThat(call("GET", "/accounts/me", expired, null).statusCode()).isEqualTo(401);
        String forged = login.path("accessToken").asText();
        int dot = forged.lastIndexOf('.') + 1;
        forged = forged.substring(0,dot) + (forged.charAt(dot) == 'A' ? 'B' : 'A') + forged.substring(dot+1);
        assertThat(call("GET", "/accounts/me", forged, null).statusCode()).isEqualTo(401);
    }

    @Test void signupUsesRealSmtpAndReturnsServerIdentityWithEmptyAccounts() throws Exception {
        String name = "new." + UUID.randomUUID().toString().substring(0,8);
        String email = name + "@example.test";
        requestOtp(email.toUpperCase(Locale.ROOT), "SIGNUP");
        var request = new LinkedHashMap<String,Object>(Map.of("username",name,"email",email.toUpperCase(Locale.ROOT),
                "password",PASSWORD,"otpCode",SMTP.code(email),"deviceFingerprint","signup-device","deviceName","Android emulator"));
        var response = call("POST", "/auth/register", null, request);
        assertThat(response.statusCode()).isEqualTo(201);
        JsonNode data = body(response).path("data");
        assertThat(data.path("email").asText()).isEqualTo(email);
        assertThat(data.path("userId").asLong()).isPositive();
        assertThat(data.path("roles").toString()).contains("ROLE_CUSTOMER");
        assertThat(data.path("expiresInMs").asLong()).isEqualTo(900000L);
        String access = data.path("accessToken").asText();
        var me = call("GET", "/auth/me", access, null);
        assertThat(me.statusCode()).isEqualTo(200);
        assertThat(body(me).path("data").path("userId").asLong()).isEqualTo(data.path("userId").asLong());
        assertThat(me.body()).doesNotContain("password", "otpCode", "refreshToken");
        var list = call("GET", "/accounts/me", access, null);
        assertThat(list.statusCode()).isEqualTo(200);
        assertThat(body(list).path("data").size()).isZero();
        OtpVerification stored = latest(email,"SIGNUP");
        assertThat(stored.getOtpCode()).startsWith("$2").isNotEqualTo(SMTP.code(email));
        assertThat(stored.isVerified()).isTrue();
    }

    @Test void customerCanReadOnlyTheirOwnBankingData() throws Exception {
        String alice = login("alice.demo", "alice-device").path("accessToken").asText();
        assertThat(call("GET", "/accounts/9000000001", alice, null).statusCode()).isEqualTo(200);
        assertThat(call("GET", "/accounts/9000000002", alice, null).statusCode()).isEqualTo(404);
        assertThat(call("PATCH", "/accounts/9000000002/status", alice, Map.of("status","FROZEN")).statusCode()).isEqualTo(404);
        assertThat(call("GET", "/transactions/account/9000000002", alice, null).statusCode()).isEqualTo(404);
        var account = accounts.findByAccountNumber("9000000002").orElseThrow();
        String ref = "TEST-" + UUID.randomUUID().toString().substring(0, 30);
        transactions.save(Transaction.builder().referenceNumber(ref).destinationAccount(account)
                .amount(BigDecimal.TEN).fee(BigDecimal.ZERO).currency("USD")
                .transactionType(TransactionType.DEPOSIT).status(TransactionStatus.SUCCESS).build());
        assertThat(call("GET", "/transactions/"+ref, alice, null).statusCode()).isEqualTo(404);
        String bob = login("bob.demo", "bob-device").path("accessToken").asText();
        assertThat(call("GET", "/transactions/"+ref, bob, null).statusCode()).isEqualTo(200);
        String hash = UUID.randomUUID().toString().replace("-", "");
        payments.save(com.bank.digital_banking.module.payment.entity.Payment.builder()
                .md5Hash(hash).accountNumber("9000000002").amount(BigDecimal.TEN).currency("USD")
                .status(com.bank.digital_banking.module.payment.entity.PaymentStatus.SUCCESS).build());
        assertThat(call("GET", "/payments/verify/"+hash, alice, null).statusCode()).isEqualTo(404);
        assertThat(call("GET", "/payments/verify/"+hash, bob, null).statusCode()).isEqualTo(200);
        assertThat(call("POST", "/payments/khqr/generate", alice,
                Map.of("accountNumber", "9000000002", "amount",10,"currency","USD")).statusCode()).isEqualTo(404);
        assertThat(call("POST", "/transactions/transfer", alice, Map.of("sourceAccountNumber","9000000002",
                "destinationAccountNumber","9000000001","amount",1,"currency","USD")).statusCode()).isEqualTo(404);
    }

    @Test void rolesCannotCrossCustomerAndOperationsBoundaries() throws Exception {
        String customer = login("alice.demo", "role-customer").path("accessToken").asText();
        assertThat(call("GET", "/fraud/flagged", customer, null).statusCode()).isEqualTo(403);
        assertThat(call("GET", "/audit/module/AUTH", customer, null).statusCode()).isEqualTo(403);
        assertThat(call("POST", "/transactions/deposit", customer, Map.of("accountNumber","9000000001","amount",1,"currency","USD")).statusCode()).isEqualTo(403);
        assertThat(call("POST", "/payments/webhook", customer, Map.of("md5","client-cannot-confirm-payments")).statusCode()).isEqualTo(403);
        assertThat(call("POST", "/accounts", customer, Map.of("accountType","SAVINGS","currency","USD","initialDeposit",100)).statusCode()).isEqualTo(400);
        for (String name : List.of("employee.demo","merchant.demo","admin.demo")) {
            String token = login(name, "role-"+name).path("accessToken").asText();
            assertThat(call("GET", "/accounts/me", token, null).statusCode()).isEqualTo(403);
            assertThat(call("GET", "/auth/me", token, null).statusCode()).isEqualTo(200);
        }
    }

    @Test void refreshRotatesAndReuseRevokesTheEntireSession() throws Exception {
        JsonNode initial = login("alice.demo", "refresh-device");
        assertThat(call("POST", "/auth/refresh", null, Map.of("refreshToken",initial.path("accessToken").asText())).statusCode()).isEqualTo(401);
        var refreshed = call("POST", "/auth/refresh", null, Map.of("refreshToken",initial.path("refreshToken").asText()));
        assertThat(refreshed.statusCode()).isEqualTo(200);
        JsonNode data = body(refreshed).path("data");
        assertThat(data.path("refreshToken").asText()).isNotEqualTo(initial.path("refreshToken").asText());
        assertThat(call("GET", "/accounts/me", data.path("accessToken").asText(), null).statusCode()).isEqualTo(200);
        var replay = call("POST", "/auth/refresh", null, Map.of("refreshToken",initial.path("refreshToken").asText()));
        assertThat(replay.statusCode()).isEqualTo(401);
        assertThat(body(replay).path("error").asText()).isEqualTo("REFRESH_REUSED");
        assertThat(call("GET", "/accounts/me", data.path("accessToken").asText(), null).statusCode()).isEqualTo(401);
        assertThat(call("POST", "/auth/refresh", null, Map.of("refreshToken",data.path("refreshToken").asText())).statusCode()).isEqualTo(401);
        assertThat(sessions.findById(UUID.fromString(initial.path("sessionId").asText())).orElseThrow().getRefreshTokenHash())
                .hasSize(64).doesNotContain(initial.path("refreshToken").asText());
    }

    @Test void simultaneousRefreshCannotIssueTwoUsableSuccessors() throws Exception {
        JsonNode initial = login("alice.demo", "refresh-race-device");
        List<HttpResponse<String>> results = concurrent(() -> call("POST","/auth/refresh",null,
                Map.of("refreshToken",initial.path("refreshToken").asText())));
        assertThat(results.stream().map(HttpResponse::statusCode).sorted().toList()).containsExactly(200,401);
        var success = results.stream().filter(r -> r.statusCode()==200).findFirst().orElseThrow();
        assertThat(call("GET","/accounts/me",body(success).path("data").path("accessToken").asText(),null).statusCode()).isEqualTo(401);
    }

    @Test void logoutRevokesBothTokensButLeavesAnotherDeviceSignedIn() throws Exception {
        JsonNode first = login("alice.demo", "logout-first");
        // Advance resend metadata rather than sleeping for a minute.
        allowResend("alice.demo@example.test", "LOGIN");
        JsonNode second = login("alice.demo", "logout-second");
        assertThat(call("POST","/auth/logout",first.path("accessToken").asText(),Map.of()).statusCode()).isEqualTo(200);
        assertThat(call("GET","/accounts/me",first.path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        assertThat(call("POST","/auth/refresh",null,Map.of("refreshToken",first.path("refreshToken").asText())).statusCode()).isEqualTo(401);
        assertThat(call("GET","/accounts/me",second.path("accessToken").asText(),null).statusCode()).isEqualTo(200);
    }

    @Test void disabledUserAndRevokedDeviceAreRejectedForLoginAccessAndRefresh() throws Exception {
        JsonNode first = login("alice.demo", "disabled-user");
        User user = users.findByUsername("alice.demo").orElseThrow();
        user.setEnabled(false); users.save(user);
        assertThat(call("GET","/accounts/me",first.path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        assertThat(call("POST","/auth/refresh",null,Map.of("refreshToken",first.path("refreshToken").asText())).statusCode()).isEqualTo(401);
        assertThat(call("POST","/auth/login",null,loginRequest("alice.demo",SMTP.code(user.getEmail()),"disabled-user")).statusCode()).isEqualTo(401);
        user.setEnabled(true); users.save(user);
        Device device = devices.findByUserAndDeviceFingerprint(user,"disabled-user").orElseThrow();
        device.setStatus(DeviceStatus.REVOKED); devices.save(device);
        assertThat(call("GET","/accounts/me",first.path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        assertThat(call("POST","/auth/refresh",null,Map.of("refreshToken",first.path("refreshToken").asText())).statusCode()).isEqualTo(401);
        allowResend(user.getEmail(),"LOGIN"); requestOtp(user.getEmail(),"LOGIN");
        var rejected = call("POST","/auth/login",null,loginRequest("alice.demo",SMTP.code(user.getEmail()),"disabled-user"));
        assertThat(body(rejected).path("error").asText()).isEqualTo("DEVICE_REVOKED");
    }

    @Test void sharedInstallationHasIndependentUserDeviceRecords() throws Exception {
        JsonNode alice = login("alice.demo","shared-installation");
        JsonNode bob = login("bob.demo","shared-installation");
        assertThat(call("GET","/auth/me",alice.path("accessToken").asText(),null).statusCode()).isEqualTo(200);
        assertThat(call("GET","/auth/me",bob.path("accessToken").asText(),null).statusCode()).isEqualTo(200);
        assertThat(devices.findAll().stream().filter(d -> d.getDeviceFingerprint().equals("shared-installation")).count()).isEqualTo(2);
    }

    @Test void otpWrongAttemptsPersistAcrossFailedLoginTransactions() throws Exception {
        String email = "alice.demo@example.test";
        requestOtp(email,"LOGIN");
        String wrong = SMTP.code(email).equals("000000") ? "111111" : "000000";
        for(int i=1;i<=5;i++) {
            var response = call("POST","/auth/login",null,loginRequest("alice.demo",wrong,"otp-attempts"));
            assertThat(response.statusCode()).isEqualTo(401);
            assertThat(latest(email,"LOGIN").getAttempts()).isEqualTo(i);
        }
        var locked = call("POST","/auth/login",null,loginRequest("alice.demo",SMTP.code(email),"otp-attempts"));
        assertThat(body(locked).path("error").asText()).isEqualTo("OTP_ATTEMPTS_EXCEEDED");
        allowResend(email,"LOGIN");
        JsonNode fresh = login("alice.demo","otp-attempts");
        assertThat(fresh.path("accessToken").asText()).isNotBlank();
    }

    @Test void expiredAndConsumedOtpsCannotBeUsed() throws Exception {
        String email = "alice.demo@example.test";
        requestOtp(email,"LOGIN");
        OtpVerification otp = latest(email,"LOGIN");
        otp.setExpiresAt(OffsetDateTime.now().minusSeconds(1)); otps.save(otp);
        var expired = call("POST","/auth/login",null,loginRequest("alice.demo",SMTP.code(email),"expiry-device"));
        assertThat(body(expired).path("error").asText()).isEqualTo("OTP_EXPIRED");
        allowResend(email,"LOGIN"); login("alice.demo","expiry-device");
        var used = call("POST","/auth/login",null,loginRequest("alice.demo",SMTP.code(email),"expiry-device"));
        assertThat(body(used).path("error").asText()).isEqualTo("OTP_USED");
    }

    @Test void otpResendAndWindowLimitsHaveRetryAfterAndReset() throws Exception {
        String email = "limits@example.test";
        requestOtp(email,"SIGNUP");
        var limited = call("POST","/auth/request-otp",null,Map.of("email",email,"purpose","SIGNUP"));
        assertThat(limited.statusCode()).isEqualTo(429);
        assertThat(limited.headers().firstValue("Retry-After")).isPresent();
        assertThat(body(limited).path("retryAfterSeconds").asLong()).isBetween(1L,60L);
        for(int i=0;i<4;i++) { allowResend(email,"SIGNUP"); requestOtp(email,"SIGNUP"); }
        allowResend(email,"SIGNUP");
        assertThat(call("POST","/auth/request-otp",null,Map.of("email",email,"purpose","SIGNUP")).statusCode()).isEqualTo(429);
        OtpRateLimit row = limits.findById(email+"|SIGNUP").orElseThrow();
        row.setWindowStartedAt(OffsetDateTime.now().minusMinutes(16)); limits.save(row);
        requestOtp(email,"SIGNUP");
        assertThat(limits.findById(email+"|SIGNUP").orElseThrow().getRequestCount()).isEqualTo(1);
    }

    @Test void concurrentOtpRequestsAreThrottledAtTheDatabase() throws Exception {
        var results = concurrent(() -> call("POST","/auth/request-otp",null,
                Map.of("email","concurrent@example.test","purpose","SIGNUP")));
        assertThat(results.stream().map(HttpResponse::statusCode).sorted().toList()).containsExactly(200,429);
        assertThat(otps.count()).isEqualTo(1);
    }

    @Test void smtpFailuresDoNotReturnSuccessOrPersistUsableCodes() throws Exception {
        SMTP.rejectNext.set(true);
        var response = call("POST","/auth/request-otp",null,Map.of("email","mailfailure@example.test","purpose","SIGNUP"));
        assertThat(response.statusCode()).isEqualTo(503);
        assertThat(body(response).path("error").asText()).isEqualTo("OTP_DELIVERY_UNAVAILABLE");
        assertThat(otps.count()).isZero();
    }

    @Test void publicOtpResponseAndValidationErrorsDoNotLeakSecrets() throws Exception {
        var unknown = call("POST","/auth/request-otp",null,Map.of("email","unknown@example.test","purpose","LOGIN"));
        var known = call("POST","/auth/request-otp",null,Map.of("email","alice.demo@example.test","purpose","LOGIN"));
        assertThat(unknown.statusCode()).isEqualTo(200);
        assertThat(body(unknown).path("data")).isEqualTo(body(known).path("data"));
        assertThat(known.body()).doesNotContain(SMTP.code("alice.demo@example.test"));
        var invalid = call("POST","/auth/request-otp",null,Map.of("email","bad","purpose","RESET"));
        assertThat(invalid.statusCode()).isEqualTo(400);
        assertThat(body(invalid).path("error").asText()).isEqualTo("VALIDATION_FAILED");
        assertThat(body(invalid).path("fieldErrors").has("email")).isTrue();
        var badJson = raw("POST","/api/v1/auth/login",null,"{");
        assertThat(badJson.statusCode()).isEqualTo(400);
        assertThat(body(badJson).path("error").asText()).isEqualTo("INVALID_REQUEST");
    }

    @Test void localFixturesAndOpenApiAreReadyForFlutter() throws Exception {
        assertThat(accounts.findByAccountNumber("9000000001").orElseThrow().getBalance()).isEqualByComparingTo("1250.00");
        assertThat(accounts.findByUser(users.findByUsername("empty.demo").orElseThrow())).isEmpty();
        var docs = raw("GET","/v3/api-docs",null,null);
        assertThat(docs.statusCode()).isEqualTo(200);
        assertThat(body(docs).path("paths").has("/api/v1/auth/logout")).isTrue();
        assertThat(body(docs).path("paths").has("/api/v1/auth/me")).isTrue();
        assertThat(body(docs).path("components").path("securitySchemes").has("bearerAuth")).isTrue();
    }

    @Test void repeatedLoginReplacesOnlyThatUserAndInstallationSession() throws Exception {
        JsonNode first = login("alice.demo","replace-session");
        allowResend("alice.demo@example.test","LOGIN");
        JsonNode next = login("alice.demo","replace-session");
        assertThat(call("GET","/auth/me",first.path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        assertThat(call("GET","/auth/me",next.path("accessToken").asText(),null).statusCode()).isEqualTo(200);
    }

    @Test void absoluteSessionExpiryRejectsBothTokenTypes() throws Exception {
        JsonNode initial = login("alice.demo","absolute-expiry");
        AuthSession session = sessions.findById(UUID.fromString(initial.path("sessionId").asText())).orElseThrow();
        session.setExpiresAt(OffsetDateTime.now().minusSeconds(1)); sessions.save(session);
        assertThat(call("GET","/accounts/me",initial.path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        assertThat(call("POST","/auth/refresh",null,Map.of("refreshToken",initial.path("refreshToken").asText())).statusCode()).isEqualTo(401);
    }

    @Test void wrongPasswordAndInvalidPayloadDoNotCreateSessions() throws Exception {
        requestOtp("alice.demo@example.test","LOGIN");
        var request = new LinkedHashMap<>(loginRequest("alice.demo",SMTP.code("alice.demo@example.test"),"wrong-password"));
        request.put("password","wrong-password");
        assertThat(call("POST","/auth/login",null,request).statusCode()).isEqualTo(401);
        assertThat(latest("alice.demo@example.test","LOGIN").isVerified()).isFalse();
        assertThat(sessions.count()).isZero();
        request.put("otpCode","");
        var response = call("POST","/auth/login",null,request);
        assertThat(response.statusCode()).isEqualTo(400);
        assertThat(body(response).path("fieldErrors").has("otpCode")).isTrue();
    }

    @Test void consumedReplacementOtpNeverFallsBackToAnOlderChallenge() throws Exception {
        String email="alice.demo@example.test";
        requestOtp(email,"LOGIN");
        String olderCode=SMTP.code(email);
        allowResend(email,"LOGIN");
        login("alice.demo","latest-otp");
        var old = call("POST","/auth/login",null,loginRequest("alice.demo",olderCode,"latest-otp"));
        assertThat(body(old).path("error").asText()).isEqualTo("OTP_USED");
    }

    @Test void serverIdentityControlsAiRecordsInsteadOfSubmittedUserId() throws Exception {
        JsonNode alice = login("alice.demo","scoped-ai");
        Long bob=users.findByUsername("bob.demo").orElseThrow().getId();
        String token=alice.path("accessToken").asText();
        assertThat(call("GET","/ai/insights/user/"+bob,token,null).statusCode()).isEqualTo(404);
        var response=call("POST","/ai/insights/spending",token,Map.of("userId",bob,"targetPeriod","test-"+UUID.randomUUID().toString().substring(0,8),
                "categorySpends",List.of(Map.of("category","Food","amount",15))));
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        assertThat(body(response).path("userId").asLong()).isEqualTo(alice.path("userId").asLong());
    }

    @Test void localSeederCannotBeEnabledUnderAProductionProfile() {
        try(var context=new org.springframework.context.annotation.AnnotationConfigApplicationContext()) {
            context.getEnvironment().setActiveProfiles("local","prod");
            context.getEnvironment().getPropertySources().addFirst(new org.springframework.core.env.MapPropertySource(
                    "explicit-seed-request", Map.of("app.dev.seed.enabled", "true", "app.dev.seed.password", PASSWORD)));
            context.register(com.bank.digital_banking.config.LocalDevelopmentData.class);
            context.refresh();
            assertThat(context.getBeansOfType(com.bank.digital_banking.config.LocalDevelopmentData.class)).isEmpty();
        }
    }

    JsonNode login(String username,String device) throws Exception {
        requestOtp(username+"@example.test","LOGIN");
        var response = call("POST","/auth/login",null,loginRequest((username+"@example.test").toUpperCase(Locale.ROOT),SMTP.code(username+"@example.test"),device));
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        return body(response).path("data");
    }
    Map<String,Object> loginRequest(String username,String code,String device) {
        return Map.of("usernameOrEmail",username,"password",PASSWORD,"otpCode",code,
                "deviceFingerprint",device,"deviceName","Android emulator","deviceType","ANDROID");
    }
    void requestOtp(String email,String purpose) throws Exception {
        var response = call("POST","/auth/request-otp",null,Map.of("email",email,"purpose",purpose));
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
    }
    void allowResend(String email,String purpose) {
        OtpRateLimit row = limits.findById(email+"|"+purpose).orElseThrow();
        row.setLastRequestedAt(OffsetDateTime.now().minusSeconds(61)); limits.save(row);
    }
    OtpVerification latest(String email,String purpose) {
        return otps.findTopByEmailAndPurposeOrderByCreatedAtDescIdDesc(email,purpose).orElseThrow();
    }
    JsonNode body(HttpResponse<String> response) { return json.readTree(response.body()); }
    HttpResponse<String> call(String method,String path,String token,Object data) throws Exception {
        return raw(method,"/api/v1"+path,token,data==null?null:json.writeValueAsString(data));
    }
    HttpResponse<String> raw(String method,String path,String token,String data) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://localhost:"+port+path)).timeout(Duration.ofSeconds(20));
        if(token!=null) request.header("Authorization","Bearer "+token);
        if(data!=null) request.header("Content-Type","application/json");
        return client.send(request.method(method,data==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(data)).build(),HttpResponse.BodyHandlers.ofString());
    }
    List<HttpResponse<String>> concurrent(Callable<HttpResponse<String>> action) throws Exception {
        try(var pool=Executors.newVirtualThreadPerTaskExecutor()) {
            CountDownLatch ready=new CountDownLatch(2), start=new CountDownLatch(1);
            Callable<HttpResponse<String>> work=()->{ready.countDown(); if(!start.await(10,TimeUnit.SECONDS)) throw new IllegalStateException(); return action.call();};
            var a=pool.submit(work); var b=pool.submit(work);
            assertThat(ready.await(10,TimeUnit.SECONDS)).isTrue(); start.countDown();
            return List.of(a.get(30,TimeUnit.SECONDS),b.get(30,TimeUnit.SECONDS));
        }
    }
}
