package com.bank.digital_banking;

import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.module.auth.dto.TokenResponseDto;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.security.JwtTokenProvider;
import com.bank.digital_banking.module.auth.service.*;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthRetention;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import tools.jackson.databind.*;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import static org.assertj.core.api.Assertions.*;

/** HTTP security/transaction tests use only embedded PostgreSQL and synthetic PINs. */
class MerchantAuthTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired UserRepository users;
    @Autowired RoleRepository roles;
    @Autowired SessionService sessions;
    @Autowired DeviceService devices;
    @Autowired PlatformTransactionManager txManager;
    @Autowired JwtTokenProvider jwt;
    @Autowired MerchantAuthRetention retention;
    final HttpClient http=HttpClient.newHttpClient();
    static final String CALLBACK="kesormerchant://auth/callback";
    static final String CLIENT="kesor-merchant-android";
    static final SecureRandom RANDOM=new SecureRandom();
    record Customer(long id, UUID sid, String token, String refresh, String ticket) {}
    record Attempt(UUID id, String handoff, String verifier, String secret, String state, String exchangeKey) {}

    @BeforeEach void limits() { jdbc.update("DELETE FROM merchant_auth_limits"); }

    @Test void validApprovalIssuesOnlyMerchantCredentialsAndSeparateSession() throws Exception {
        var c=customer(); var a=start();
        var details=call("GET",path(a),c.token(),null,Map.of("X-Merchant-Handoff",a.handoff()));
        assertThat(details.statusCode()).as(details.body()).isEqualTo(200);
        assertThat(data(details).path("clientName").asText()).isEqualTo("Kesor Merchant");
        assertThat(details.body()).doesNotContain(c.token(),a.secret(),a.handoff(),a.verifier());
        String code=approve(c,a);
        var response=exchange(a,code); assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        var t=data(response); String token=t.path("accessToken").asText();
        var claims=jwt.parse(token,"access");
        assertThat(claims.getAudience()).containsExactly("kesor-merchant");
        assertThat(claims.get("purpose")).isEqualTo("MERCHANT");
        assertThat(claims.get("client_id")).isEqualTo(CLIENT);
        assertThat(t.path("roles").toString()).doesNotContain("ROLE_CUSTOMER","ROLE_ADMIN","ROLE_MERCHANT");
        assertThat(t.path("expiresInMs").asLong()).isEqualTo(300000);
        assertThat(t.path("sessionId").asText()).isNotEqualTo(c.sid().toString());
        var identity=call("GET","/merchant-auth/session",token,null);
        assertThat(identity.statusCode()).isEqualTo(200);
        assertThat(data(identity).path("ownerId").asLong()).isEqualTo(c.id());
        assertThat(data(identity).path("onboardingState").asText()).isEqualTo("SHOP_REQUIRED");
        assertThat(data(identity).path("shop").isNull()).isTrue();
        assertThat(call("GET","/auth/me",c.token(),null).statusCode()).isEqualTo(200);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM auth_sessions WHERE user_id=? AND revoked_at IS NULL",Integer.class,c.id())).isEqualTo(2);
        assertThat(response.headers().firstValue("Cache-Control").orElse("")).contains("no-store");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM transfer_pin_proofs WHERE user_id=?",Integer.class,c.id())).isZero();
        String audit=String.join(" ",jdbc.queryForList("SELECT coalesce(details,'') || coalesce(target_resource_id,'') FROM audit_logs WHERE module_name='MERCHANT_AUTH'",String.class));
        assertThat(audit).doesNotContain(code,a.handoff(),a.secret(),a.verifier(),token,t.path("refreshToken").asText(),CALLBACK);
    }

    @Test void arbitraryClientsCallbacksAndMalformedPkceAreRejectedBeforePersistence() throws Exception {
        var body=startBody();
        for (var bad:List.of(Map.entry("redirectUri",CALLBACK+"?evil=1"),Map.entry("redirectUri","https://attacker.example/callback"),
                Map.entry("clientId","foreign-client"),Map.entry("codeChallengeMethod","plain"),Map.entry("codeChallenge","short"),
                Map.entry("attemptSecretHash","0"),Map.entry("state","bad&state"),Map.entry("deviceName","bad\nname"))) {
            var changed=new HashMap<>(body); changed.put(bad.getKey(),bad.getValue());
            assertThat(call("POST","/merchant-auth/attempts",null,changed).statusCode()).as(bad.toString()).isEqualTo(400);
        }
    }

    @Test void approvalRequiresCustomerHandoffAndFreshPinAndPreservesFailedCounter() throws Exception {
        var c=customer(); var a=start();
        assertThat(call("GET",path(a),c.token(),null).statusCode()).isEqualTo(400);
        assertThat(call("GET",path(a),c.token(),null,Map.of("X-Merchant-Handoff",random())).statusCode()).isEqualTo(400);
        assertThat(call("POST",path(a)+"/approve",null,Map.of("handoffToken",a.handoff(),"pin","0427")).statusCode()).isEqualTo(401);
        assertThat(call("POST",path(a)+"/approve",c.token(),Map.of("handoffToken",random(),"pin","9999")).statusCode()).isEqualTo(400);
        assertThat(failures(c)).isZero();
        var proof=call("POST","/auth/pin/transfer-proof",c.token(),Map.of("pin","0427"));
        assertThat(proof.statusCode()).isEqualTo(200);
        var wrongPurpose=call("POST",path(a)+"/approve",c.token(),Map.of("handoffToken",a.handoff(),"proof",data(proof).path("proof").asText()));
        assertThat(wrongPurpose.statusCode()).isEqualTo(400);
        var wrong=call("POST",path(a)+"/approve",c.token(),Map.of("handoffToken",a.handoff(),"pin","9999"));
        assertThat(error(wrong)).isEqualTo("PIN_INVALID"); assertThat(failures(c)).isEqualTo(1);
        // A different PIN operation sees that same durable budget.
        call("POST","/auth/pin/transfer-proof",c.token(),Map.of("pin","9999"));
        assertThat(failures(c)).isEqualTo(2);
        approve(c,a); assertThat(failures(c)).isZero();
        assertThat(call("POST",path(a)+"/approve",c.token(),Map.of("handoffToken",a.handoff(),"pin","0427")).statusCode()).isEqualTo(409);
    }

    @Test void fifthBadApprovalLocksCustomerAndCannotBeBypassedWithNewAttempt() throws Exception {
        var c=customer(); var a=start();
        for(int i=1;i<=5;i++) {
            var r=call("POST",path(a)+"/approve",c.token(),Map.of("handoffToken",a.handoff(),"pin","9999"));
            assertThat(error(r)).isEqualTo(i==5?"PIN_RECOVERY_REQUIRED":"PIN_INVALID");
            assertThat(failures(c)).isEqualTo(i);
        }
        var another=start();
        assertThat(error(call("POST",path(another)+"/approve",c.token(),Map.of("handoffToken",another.handoff(),"pin","0427")))).isEqualTo("PIN_REQUIRED");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM auth_sessions WHERE user_id=? AND purpose='MERCHANT'",Integer.class,c.id())).isZero();
    }

    @Test void wrongExchangeInputsNeverConsumeApproval() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a);
        var body=exchangeBody(a,code);
        for(var bad:List.of(Map.entry("codeVerifier",random()),Map.entry("attemptSecret",random()),Map.entry("code",random()),
                Map.entry("state",random()),Map.entry("redirectUri",CALLBACK+"/"),Map.entry("clientId","other-client"))) {
            var changed=new HashMap<>(body); changed.put(bad.getKey(),bad.getValue());
            assertThat(call("POST","/merchant-auth/exchange",null,changed).statusCode()).as(bad.getKey()).isEqualTo(400);
        }
        assertThat(status(a)).isEqualTo("APPROVED");
        assertThat(exchange(a,code).statusCode()).isEqualTo(200);
    }

    @Test void deniedCancelledAndExpiredAttemptsCannotExchange() throws Exception {
        var c=customer(); var denied=start();
        var r=call("POST",path(denied)+"/deny",c.token(),Map.of("handoffToken",denied.handoff()));
        assertThat(r.statusCode()).isEqualTo(200);
        String uri=data(r).path("callbackUri").asText();
        assertThat(uri).startsWith(CALLBACK+"?error=access_denied&state=").doesNotContain("code=");
        assertThat(status(denied)).isEqualTo("DENIED");
        assertThat(error(exchange(denied,random()))).isEqualTo("MERCHANT_AUTH_DENIED");
        var cancelled=start(); String code=approve(c,cancelled); cancel(cancelled);
        assertThat(error(exchange(cancelled,code))).isEqualTo("MERCHANT_AUTH_CANCELLED");
        var expired=start(); String old=approve(c,expired);
        expire(expired);
        assertThat(error(exchange(expired,old))).isEqualTo("MERCHANT_AUTH_EXPIRED");
        assertThat(status(expired)).isEqualTo("EXPIRED");
        var pending=start(); expire(pending);
        assertThat(error(call("POST",path(pending)+"/approve",c.token(),Map.of("handoffToken",pending.handoff(),"pin","0427")))).isEqualTo("MERCHANT_AUTH_EXPIRED");
    }

    @Test void statusAndCancellationRequirePrivateSecretAndNeverRevealCredentials() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a);
        for(String action:List.of("status","cancel")) {
            var bad=call("POST",path(a)+"/"+action,null,Map.of("attemptSecret",random()));
            assertThat(bad.statusCode()).isEqualTo(400);
            assertThat(bad.headers().firstValue("Cache-Control").orElse("")).contains("no-store");
        }
        var state=call("POST",path(a)+"/status",null,Map.of("attemptSecret",a.secret()));
        assertThat(state.body()).doesNotContain(code,a.handoff(),a.secret(),"accessToken","refreshToken","ownerId");
        assertThat(status(a)).isEqualTo("APPROVED");
    }

    @Test void lostExchangeResponseRecoversSameEncryptedReceiptAndCannotCreateSecondSession() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a);
        var first=exchange(a,code); var second=exchange(a,code);
        assertThat(data(second)).isEqualTo(data(first));
        assertThat(jdbc.queryForObject("SELECT count(*) FROM auth_sessions WHERE user_id=? AND purpose='MERCHANT'",Integer.class,c.id())).isEqualTo(1);
        String stored=jdbc.queryForObject("SELECT recovery_ciphertext FROM merchant_auth_attempts WHERE id=?",String.class,a.id());
        assertThat(stored).doesNotContain(data(first).path("refreshToken").asText(),data(first).path("accessToken").asText(),"Bearer");
        var changed=new HashMap<>(exchangeBody(a,code)); changed.put("exchangeKey",random());
        assertThat(error(call("POST","/merchant-auth/exchange",null,changed))).isEqualTo("MERCHANT_AUTH_USED");
        jdbc.update("UPDATE merchant_auth_attempts SET recovery_expires_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=?",a.id());
        assertThat(error(exchange(a,code))).isEqualTo("MERCHANT_AUTH_USED");
    }

    @Test void simultaneousExchangesReturnOneSessionAndSameTokens() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a);
        var results=race(()->exchange(a,code),()->exchange(a,code));
        assertThat(results).allSatisfy(r->assertThat(r.statusCode()).as(r.body()).isEqualTo(200));
        assertThat(data(results.get(0))).isEqualTo(data(results.get(1)));
        assertThat(jdbc.queryForObject("SELECT count(*) FROM auth_sessions WHERE user_id=? AND purpose='MERCHANT'",Integer.class,c.id())).isEqualTo(1);
    }

    @Test void competingExchangeKeysCannotCreateTwoSessions() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a);
        var other=new HashMap<>(exchangeBody(a,code)); other.put("exchangeKey",random());
        var results=race(()->exchange(a,code),()->call("POST","/merchant-auth/exchange",null,other));
        assertThat(results.stream().map(HttpResponse::statusCode)).containsExactlyInAnyOrder(200,409);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM auth_sessions WHERE user_id=? AND purpose='MERCHANT'",Integer.class,c.id())).isEqualTo(1);
    }

    @Test void cancellationExchangeRaceNeverLeavesAUsableSession() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a);
        var results=race(()->exchange(a,code),()->call("POST",path(a)+"/cancel",null,Map.of("attemptSecret",a.secret())));
        assertThat(results.get(1).statusCode()).as(results.get(1).body()).isEqualTo(200);
        assertThat(results.get(0).statusCode()).isIn(200,409);
        assertThat(status(a)).isEqualTo("CANCELLED");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM auth_sessions WHERE user_id=? AND purpose='MERCHANT' AND revoked_at IS NULL",Integer.class,c.id())).isZero();
        if(results.get(0).statusCode()==200) assertThat(call("GET","/merchant-auth/session",data(results.get(0)).path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        assertThat(exchange(a,code).statusCode()).isEqualTo(409);
    }

    @Test void approvalCancellationRaceHasOneTerminalOutcome() throws Exception {
        var c=customer(); var a=start();
        var results=race(()->call("POST",path(a)+"/approve",c.token(),Map.of("handoffToken",a.handoff(),"pin","0427")),
                ()->call("POST",path(a)+"/cancel",null,Map.of("attemptSecret",a.secret())));
        assertThat(results.get(0).statusCode()).isIn(200,409);
        assertThat(results.get(1).statusCode()).as(results.get(1).body()).isEqualTo(200);
        assertThat(status(a)).isEqualTo("CANCELLED");
    }

    @Test void merchantTokenCannotReachPersonalOrLegacyMerchantApisEvenWithDualRoles() throws Exception {
        var c=customer();
        jdbc.update("INSERT INTO user_roles(user_id,role_id) SELECT ?,id FROM roles WHERE name='ROLE_MERCHANT'",c.id());
        var a=start(); String token=data(exchange(a,approve(c,a))).path("accessToken").asText();
        for(String path:List.of("/auth/me","/accounts/me","/transactions/search","/analytics/monthly-overview",
                // /merchants/me itself became the M4 Merchant-session shop route; the legacy accounts route stays closed.
                "/ai/conversations","/merchants/me/accounts","/merchants","/payments/qr/status/anything","/auth/merchant-sessions")) {
            var r=call("GET",path,token,null);
            assertThat(r.statusCode()).as(path+": "+r.body()).isEqualTo(403);
            assertThat(error(r)).isEqualTo("CUSTOMER_SESSION_REQUIRED");
        }
        for(String path:List.of("/auth/pin/prepare","/auth/pin/change","/auth/pin/transfer-proof","/auth/logout",
                "/merchants/register","/transactions/transfer","/payments/qr/transfer"))
            assertThat(call("POST",path,token,Map.of()).statusCode()).as(path).isEqualTo(403);
        assertThat(call("GET","/merchant-auth/session",c.token(),null).statusCode()).isEqualTo(403);
        assertThat(call("POST","/merchant-auth/logout",c.token(),null).statusCode()).isEqualTo(403);
    }

    @Test void databasePurposeRejectsValidlySignedForgedOrLegacyMerchantAudience() throws Exception {
        var c=customer(); var a=start(); var t=data(exchange(a,approve(c,a)));
        UUID sid=UUID.fromString(t.path("sessionId").asText());
        String forged=jwt.generateAccessToken(c.id(),sid,Set.of("ROLE_CUSTOMER"));
        assertThat(error(call("GET","/accounts/me",forged,null))).isEqualTo("TOKEN_INVALID");
        String merchantOnCustomer=jwt.generateMerchantToken(c.id(),c.sid(),"access");
        assertThat(error(call("GET","/merchant-auth/session",merchantOnCustomer,null))).isEqualTo("TOKEN_INVALID");
        String legacy=legacy(c.id(),sid,0);
        assertThat(error(call("GET","/accounts/me",legacy,null))).isEqualTo("TOKEN_INVALID");
        assertThat(call("GET","/auth/me",legacy(c.id(),c.sid(),1),null).statusCode()).isEqualTo(200);
    }

    @Test void refreshRotationIsPurposeBoundAndReuseRevokesOnlyMerchantSession() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a); var t=data(exchange(a,code));
        String refresh=t.path("refreshToken").asText();
        assertThat(error(call("POST","/auth/refresh",null,Map.of("refreshToken",refresh)))).isEqualTo("CUSTOMER_SESSION_REQUIRED");
        assertThat(error(call("POST","/merchant-auth/refresh",null,Map.of("refreshToken",c.refresh())))).isEqualTo("MERCHANT_SESSION_REQUIRED");
        var rotated=call("POST","/merchant-auth/refresh",null,Map.of("refreshToken",refresh));
        assertThat(rotated.statusCode()).as(rotated.body()).isEqualTo(200);
        assertThat(data(rotated).path("refreshToken").asText()).isNotEqualTo(refresh);
        assertThat(error(exchange(a,code))).isEqualTo("MERCHANT_AUTH_USED");
        assertThat(error(call("POST","/merchant-auth/refresh",null,Map.of("refreshToken",refresh)))).isEqualTo("REFRESH_REUSED");
        assertThat(call("GET","/merchant-auth/session",data(rotated).path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        assertThat(call("GET","/auth/me",c.token(),null).statusCode()).isEqualTo(200);
    }

    @Test void merchantLogoutAndOwnerRevocationBlockRecoveryAndForeignRevocation() throws Exception {
        var c=customer(); var other=customer(); var a=start(); String code=approve(c,a); var t=data(exchange(a,code));
        String sid=t.path("sessionId").asText(),token=t.path("accessToken").asText();
        var list=call("GET","/auth/merchant-sessions",c.token(),null);
        assertThat(data(list).size()).isEqualTo(1);
        assertThat(list.body()).doesNotContain("refreshToken",t.path("refreshToken").asText(),"email");
        assertThat(call("POST","/auth/merchant-sessions/"+sid+"/revoke",other.token(),null).statusCode()).isEqualTo(400);
        assertThat(call("GET","/merchant-auth/session",token,null).statusCode()).isEqualTo(200);
        assertThat(call("POST","/auth/merchant-sessions/"+sid+"/revoke",c.token(),null).statusCode()).isEqualTo(200);
        assertThat(call("GET","/merchant-auth/session",token,null).statusCode()).isEqualTo(401);
        assertThat(exchange(a,code).statusCode()).isEqualTo(409);
        var b=start(); String nextCode=approve(c,b); var next=data(exchange(b,nextCode));
        assertThat(call("POST","/merchant-auth/logout",next.path("accessToken").asText(),null).statusCode()).isEqualTo(200);
        assertThat(exchange(b,nextCode).statusCode()).isEqualTo(409);
        assertThat(call("GET","/auth/me",c.token(),null).statusCode()).isEqualTo(200);
    }

    @Test void customerPinChangeRevokesMerchantAndPendingApprovedExchange() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a); var t=data(exchange(a,code));
        var pending=start(); String pendingCode=approve(c,pending);
        var changed=call("POST","/auth/pin/change",c.token(),Map.of("currentPin","0427","pin","9274","confirmPin","9274"));
        assertThat(changed.statusCode()).as(changed.body()).isEqualTo(200);
        assertThat(call("GET","/merchant-auth/session",t.path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        // Existing approved-but-unexchanged requests must also be invalidated by a PIN change.
        assertThat(exchange(pending,pendingCode).statusCode()).isNotEqualTo(200);
        assertThat(call("GET","/auth/me",c.token(),null).statusCode()).isEqualTo(200);
    }

    @Test void customerSessionReplacementDoesNotReplaceMerchantSessionOrDevice() throws Exception {
        var c=customer(); var a=start(); var t=data(exchange(a,approve(c,a)));
        String fingerprint=jdbc.queryForObject("SELECT d.device_fingerprint FROM devices d JOIN auth_sessions s ON s.device_id=d.id WHERE s.id=?",String.class,UUID.fromString(t.path("sessionId").asText()));
        new TransactionTemplate(txManager).execute(s->{var u=users.findLockedById(c.id()).orElseThrow();
            var device=devices.bind(u,fingerprint,"Customer diagnostic","MOBILE","Android","127.0.0.1"); return sessions.create(u,device);});
        assertThat(call("GET","/merchant-auth/session",t.path("accessToken").asText(),null).statusCode()).isEqualTo(200);
    }

    @Test void disablingOwnerOrRevokingDeviceBlocksMerchantAndRecovery() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a); var t=data(exchange(a,code));
        jdbc.update("UPDATE users SET is_enabled=FALSE WHERE id=?",c.id());
        assertThat(call("GET","/merchant-auth/session",t.path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        assertThat(exchange(a,code).statusCode()).isEqualTo(401);
        jdbc.update("UPDATE users SET is_enabled=TRUE WHERE id=?",c.id());
        jdbc.update("UPDATE devices SET status='REVOKED' WHERE id=(SELECT device_id FROM auth_sessions WHERE id=?)",UUID.fromString(t.path("sessionId").asText()));
        assertThat(call("POST","/merchant-auth/refresh",null,Map.of("refreshToken",t.path("refreshToken").asText())).statusCode()).isEqualTo(401);
    }

    @Test void rateLimitsPersistRejectedAttemptsAndReturnRetryAfter() throws Exception {
        var body=startBody();
        for(int i=0;i<10;i++) assertThat(call("POST","/merchant-auth/attempts",null,body).statusCode()).isEqualTo(200);
        var limited=call("POST","/merchant-auth/attempts",null,body);
        assertThat(limited.statusCode()).isEqualTo(429);
        assertThat(error(limited)).isEqualTo("MERCHANT_AUTH_RATE_LIMITED");
        assertThat(limited.headers().firstValue("Retry-After")).contains("60");
        assertThat(jdbc.queryForObject("SELECT max(hits) FROM merchant_auth_limits WHERE id LIKE 'start-install:%'",Integer.class)).isEqualTo(11);
        assertThat(call("POST","/merchant-auth/attempts",null,body).statusCode()).isEqualTo(429);
    }

    @Test void openApiPublishesPublicPossessionEndpointsAndProtectedApprovalRoutes() throws Exception {
        var request=HttpRequest.newBuilder(URI.create("http://localhost:"+port+"/v3/api-docs/merchant-auth")).GET().build();
        var response=http.send(request,HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(200);
        var api=json.readTree(response.body()); assertThat(api.path("paths").size()).isEqualTo(12);
        for(String suffix:List.of("/attempts","/exchange","/refresh","/attempts/{id}/status","/attempts/{id}/cancel")) {
            var op=api.path("paths").path("/api/v1/merchant-auth"+suffix).path("post");
            assertThat(op.path("security").isArray()).as(suffix).isTrue(); assertThat(op.path("security").size()).isZero();
            assertThat(op.path("responses").has("429")).isTrue();
        }
        assertThat(api.path("paths").path("/api/v1/merchant-auth/attempts/{id}/approve").path("post").path("responses").has("403")).isTrue();
    }

    @Test void boundedRetentionClearsExpiredSecretsAndOldRows() throws Exception {
        var c=customer(); var a=start(); exchange(a,approve(c,a));
        jdbc.update("UPDATE merchant_auth_attempts SET recovery_expires_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=?",a.id());
        var pending=start(); expire(pending);
        retention.sweep();
        assertThat(jdbc.queryForObject("SELECT recovery_ciphertext FROM merchant_auth_attempts WHERE id=?",String.class,a.id())).isNull();
        assertThat(status(pending)).isEqualTo("EXPIRED");
        jdbc.update("UPDATE merchant_auth_attempts SET created_at=CURRENT_TIMESTAMP-INTERVAL '3 days',expires_at=CURRENT_TIMESTAMP-INTERVAL '2 days' WHERE id=?",pending.id());
        retention.sweep();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_auth_attempts WHERE id=?",Integer.class,pending.id())).isZero();
    }

    @Test void concurrentOwnersCanApproveOnlyOnceAndWinnerOwnsSession() throws Exception {
        var one=customer(); var two=customer(); var a=start();
        var result=race(()->call("POST",path(a)+"/approve",one.token(),Map.of("handoffToken",a.handoff(),"pin","0427")),
                ()->call("POST",path(a)+"/approve",two.token(),Map.of("handoffToken",a.handoff(),"pin","0427")));
        assertThat(result.stream().map(HttpResponse::statusCode)).containsExactlyInAnyOrder(200,409);
        int winner=result.get(0).statusCode()==200?0:1;
        String code=query(URI.create(data(result.get(winner)).path("callbackUri").asText()),"code");
        var session=data(exchange(a,code));
        assertThat(session.path("userId").asLong()).isEqualTo(winner==0?one.id():two.id());
    }

    @Test void customerLogoutAfterApprovalPreventsIssuingMerchantSession() throws Exception {
        var c=customer(); var a=start(); String code=approve(c,a);
        assertThat(call("POST","/auth/logout",c.token(),null).statusCode()).isEqualTo(200);
        assertThat(error(exchange(a,code))).isEqualTo("SESSION_INVALID");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM auth_sessions WHERE user_id=? AND purpose='MERCHANT'",Integer.class,c.id())).isZero();
    }

    @Test void shopStatusIsOwnerScopedAndMultipleLegacyShopsRequireRecovery() throws Exception {
        var c=customer(); var other=customer(); var a=start(); String token=data(exchange(a,approve(c,a))).path("accessToken").asText();
        shop(other.id(),"Foreign shop","ACTIVE");
        assertThat(data(call("GET","/merchant-auth/session",token,null)).path("onboardingState").asText()).isEqualTo("SHOP_REQUIRED");
        String own=shop(c.id(),"Own shop","SUSPENDED");
        var restricted=data(call("GET","/merchant-auth/session",token,null));
        assertThat(restricted.path("onboardingState").asText()).isEqualTo("RESTRICTED");
        assertThat(restricted.toString()).contains("Own shop").doesNotContain("Foreign shop");
        jdbc.update("UPDATE merchants SET status='ACTIVE' WHERE merchant_id=?",own);
        assertThat(data(call("GET","/merchant-auth/session",token,null)).path("onboardingState").asText()).isEqualTo("READY");
        shop(c.id(),"Second legacy shop","ACTIVE");
        var recovery=data(call("GET","/merchant-auth/session",token,null));
        assertThat(recovery.path("onboardingState").asText()).isEqualTo("RECOVERY_REQUIRED");
        assertThat(recovery.path("shop").isNull()).isTrue();
    }

    @Test void refreshRevocationRaceCannotLeaveUsableReplacementTokens() throws Exception {
        var c=customer(); var a=start(); var t=data(exchange(a,approve(c,a)));
        var results=race(()->call("POST","/merchant-auth/refresh",null,Map.of("refreshToken",t.path("refreshToken").asText())),
                ()->call("POST","/auth/merchant-sessions/"+t.path("sessionId").asText()+"/revoke",c.token(),null));
        assertThat(results.get(1).statusCode()).as(results.get(1).body()).isEqualTo(200);
        assertThat(results.get(0).statusCode()).isIn(200,401);
        if(results.get(0).statusCode()==200)
            assertThat(call("GET","/merchant-auth/session",data(results.get(0)).path("accessToken").asText(),null).statusCode()).isEqualTo(401);
        assertThat(call("GET","/merchant-auth/session",t.path("accessToken").asText(),null).statusCode()).isEqualTo(401);
    }

    String shop(long owner,String name,String status) {
        String id="M2-"+UUID.randomUUID();
        jdbc.update("INSERT INTO merchants(merchant_id,store_name,bakong_account_id,merchant_city,status,owner_user_id) VALUES (?,?,?,'Test city',CAST(? AS merchant_status),?)",
                id,name,id+"@test",status,owner); return id;
    }

    Customer customer() throws Exception {
        TokenResponseDto initial=new TransactionTemplate(txManager).execute(s->{
            var u=users.saveAndFlush(User.builder().username("m2."+UUID.randomUUID()).firstName("Synthetic").lastName("Owner")
                    .profileComplete(true).enabled(true).roles(new HashSet<>(Set.of(roles.findByName(ERole.ROLE_CUSTOMER).orElseThrow()))).build());
            return sessions.create(u,devices.bind(u,random(),"Customer fixture","MOBILE","Android","127.0.0.1"));
        });
        var prepared=call("POST","/auth/pin/prepare",initial.getAccessToken(),null);
        assertThat(prepared.statusCode()).as(prepared.body()).isEqualTo(200);
        String ticket=data(prepared).path("ticket").asText();
        var setup=call("POST","/auth/pin/setup",null,Map.of("ticket",ticket,"pin","0427","confirmPin","0427"));
        assertThat(setup.statusCode()).as(setup.body()).isEqualTo(200);
        return new Customer(initial.getUserId(),initial.getSessionId(),data(setup).path("accessToken").asText(),data(setup).path("refreshToken").asText(),ticket);
    }
    Map<String,Object> startBody() { return new HashMap<>(Map.of("clientId",CLIENT,"redirectUri",CALLBACK,"state",random(),
            "codeChallenge",challenge(random()),"codeChallengeMethod","S256","attemptSecretHash",HashUtils.sha256(random()),
            "installationId",random(),"deviceName","Merchant fixture")); }
    Attempt start() throws Exception {
        String verifier=random(),secret=random(),state=random(); var body=startBody();
        body.put("codeChallenge",challenge(verifier)); body.put("attemptSecretHash",HashUtils.sha256(secret)); body.put("state",state);
        var response=call("POST","/merchant-auth/attempts",null,body);
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        var value=data(response); URI uri=URI.create(value.path("approvalUri").asText());
        assertThat(uri.getScheme()).isEqualTo("kesorbank");
        assertThat(uri.getHost()).isEqualTo("merchant"); assertThat(uri.getPath()).isEqualTo("/approve");
        return new Attempt(UUID.fromString(value.path("attemptId").asText()),query(uri,"handoffToken"),verifier,secret,state,random());
    }
    String approve(Customer c,Attempt a) throws Exception {
        var response=call("POST",path(a)+"/approve",c.token(),Map.of("handoffToken",a.handoff(),"pin","0427"));
        assertThat(response.statusCode()).as(response.body()).isEqualTo(200);
        URI uri=URI.create(data(response).path("callbackUri").asText());
        assertThat(uri.toString()).startsWith(CALLBACK+"?code="); assertThat(query(uri,"state")).isEqualTo(a.state());
        assertThat(response.body()).doesNotContain("accessToken","refreshToken",c.token(),"0427");
        return query(uri,"code");
    }
    Map<String,Object> exchangeBody(Attempt a,String code) { return new HashMap<>(Map.of("attemptId",a.id().toString(),"code",code,
            "codeVerifier",a.verifier(),"attemptSecret",a.secret(),"exchangeKey",a.exchangeKey(),"state",a.state(),"clientId",CLIENT,"redirectUri",CALLBACK)); }
    HttpResponse<String> exchange(Attempt a,String code) throws Exception { return call("POST","/merchant-auth/exchange",null,exchangeBody(a,code)); }
    void cancel(Attempt a) throws Exception { assertThat(call("POST",path(a)+"/cancel",null,Map.of("attemptSecret",a.secret())).statusCode()).isEqualTo(200); }
    String status(Attempt a) throws Exception { var r=call("POST",path(a)+"/status",null,Map.of("attemptSecret",a.secret())); assertThat(r.statusCode()).as(r.body()).isEqualTo(200); return data(r).path("status").asText(); }
    int failures(Customer c) { return jdbc.queryForObject("SELECT failed_attempts FROM customer_app_pins WHERE user_id=?",Integer.class,c.id()); }
    void expire(Attempt a) { jdbc.update("UPDATE merchant_auth_attempts SET created_at=CURRENT_TIMESTAMP-INTERVAL '5 minutes',expires_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=?",a.id()); }
    String path(Attempt a) { return "/merchant-auth/attempts/"+a.id(); }
    String random() { byte[] b=new byte[32]; RANDOM.nextBytes(b); return Base64.getUrlEncoder().withoutPadding().encodeToString(b); }
    String challenge(String raw) { return Base64.getUrlEncoder().withoutPadding().encodeToString(HexFormat.of().parseHex(HashUtils.sha256(raw))); }
    String query(URI uri,String field) { return Arrays.stream(uri.getRawQuery().split("&")).map(p->p.split("=",2)).filter(p->p[0].equals(field)).findFirst().orElseThrow()[1]; }
    JsonNode data(HttpResponse<String> r) { return json.readTree(r.body()).path("data"); }
    String error(HttpResponse<String> r) { return json.readTree(r.body()).path("error").asText(); }
    String legacy(long uid,UUID sid,int epoch) {
        return Jwts.builder().issuer("digital-banking").subject(Long.toString(uid)).id(UUID.randomUUID().toString())
                .claim("sid",sid.toString()).claim("type","access").claim("pin_epoch",epoch)
                .issuedAt(new Date()).expiration(Date.from(Instant.now().plusSeconds(60)))
                .signWith(Keys.hmacShaKeyFor(Decoders.BASE64.decode(SECRET)),Jwts.SIG.HS256).compact();
    }
    List<HttpResponse<String>> race(Callable<HttpResponse<String>> one,Callable<HttpResponse<String>> two) throws Exception {
        try(var pool=Executors.newFixedThreadPool(2)) {
            var start=new CountDownLatch(1);
            var a=pool.submit(()->{start.await();return one.call();}); var b=pool.submit(()->{start.await();return two.call();});
            start.countDown(); return List.of(a.get(30,TimeUnit.SECONDS),b.get(30,TimeUnit.SECONDS));
        }
    }
    HttpResponse<String> call(String method,String path,String token,Object body) throws Exception { return call(method,path,token,body,Map.of()); }
    HttpResponse<String> call(String method,String path,String token,Object body,Map<String,String> headers) throws Exception {
        var req=HttpRequest.newBuilder(URI.create("http://localhost:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(25));
        if(token!=null) req.header("Authorization","Bearer "+token);
        if(body!=null) req.header("Content-Type","application/json"); headers.forEach(req::header);
        return http.send(req.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body))).build(),HttpResponse.BodyHandlers.ofString());
    }
}
