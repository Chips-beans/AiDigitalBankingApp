package com.bank.digital_banking;

import com.bank.digital_banking.module.account.entity.*;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.service.SessionService;
import com.bank.digital_banking.module.transaction.dto.*;
import com.bank.digital_banking.module.transaction.service.TransactionService;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.*;
import java.math.BigDecimal;
import java.net.URI;
import java.net.http.*;
import java.sql.DriverManager;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import static org.assertj.core.api.Assertions.*;

class PhaseOneFinancialTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired UserRepository users;
    @Autowired DeviceRepository devices;
    @Autowired AccountRepository accounts;
    @Autowired SessionService sessions;
    @Autowired TransactionService service;
    final HttpClient client = HttpClient.newHttpClient();
    static final AtomicLong NUMBERS = new AtomicLong(7000000000L);
    User alice, bob, staff;
    String aliceToken, bobToken, staffToken;
    Account source, destination;

    @BeforeEach void fixture() {
        alice = users.findByUsername("alice.demo").orElseThrow();
        bob = users.findByUsername("bob.demo").orElseThrow();
        staff = users.findByUsername("employee.demo").orElseThrow();
        source = account(alice, "USD", "100.00");
        destination = account(bob, "USD", "0.00");
        aliceToken = token(alice); bobToken = token(bob); staffToken = token(staff);
    }

    @Test void concurrentTransfersCannotSpendTheSameFundsTwice() throws Exception {
        var responses = parallel(() -> transfer(aliceToken, key(), source, destination, "80.00", "USD"),
                () -> transfer(aliceToken, key(), source, destination, "80.00", "USD"));
        assertThat(responses).extracting(HttpResponse::statusCode).containsExactlyInAnyOrder(200, 400);
        balance(source, "20.00"); balance(destination, "80.00");
        assertThat(postings()).isEqualTo(1);
    }

    @Test void oppositeDirectionTransfersUseOneLockOrder() throws Exception {
        jdbc.update("update accounts set balance = 100 where id = ?", destination.getId());
        var responses = parallel(() -> transfer(aliceToken, key(), source, destination, "10.00", "USD"),
                () -> transfer(bobToken, key(), destination, source, "20.00", "USD"));
        assertThat(responses).extracting(HttpResponse::statusCode).containsOnly(200);
        balance(source, "110.00"); balance(destination, "90.00");
    }

    @Test void concurrentDepositsAndTransfersDoNotLoseCredits() throws Exception {
        var responses = parallel(() -> transfer(aliceToken, key(), source, destination, "40.00", "USD"),
                () -> deposit(staffToken, key(), destination, "20.00", "USD"));
        assertThat(responses).extracting(HttpResponse::statusCode).containsOnly(200);
        balance(source, "60.00"); balance(destination, "60.00");
    }

    @Test void simultaneousDuplicatesReturnThePersistedOriginalResult() throws Exception {
        String key = key();
        var responses = parallel(() -> transfer(aliceToken, key, source, destination, "10", "usd"),
                () -> transfer(aliceToken, key, source, destination, "10.00", "USD"));
        assertThat(responses).extracting(HttpResponse::statusCode).containsOnly(200);
        assertThat(body(responses.get(0)).path("data")).isEqualTo(body(responses.get(1)).path("data"));
        balance(source, "90.00"); balance(destination, "10.00");
        assertThat(postings()).isEqualTo(1);
        String reference = body(responses.get(0)).path("data").path("referenceNumber").asText();
        assertThat(jdbc.queryForObject("select count(*) from audit_logs where action='TRANSFER' and target_resource_id=? and success", Integer.class, reference)).isEqualTo(1);
        assertThat(jdbc.queryForObject("select count(*) from idempotency_records where request_key=? and transaction_id is not null and response_json is not null", Integer.class, key)).isEqualTo(1);
        assertThat(transfer(aliceToken, key, source, destination, "10", "USD").body()).contains(reference);
    }

    @Test void keysAreBoundToThePayloadAndScopedToTheActor() throws Exception {
        String key = key();
        assertThat(transfer(aliceToken, key, source, destination, "10", "USD").statusCode()).isEqualTo(200);
        var conflict = transfer(aliceToken, key, source, destination, "11", "USD");
        assertThat(conflict.statusCode()).isEqualTo(409);
        assertThat(body(conflict).path("error").asText()).isEqualTo("IDEMPOTENCY_CONFLICT");
        assertThat(transfer(bobToken, key, destination, source, "5", "USD").statusCode()).isEqualTo(200);
        balance(source, "95.00"); balance(destination, "5.00");
    }

    @Test void depositsAreIdempotentAndRequireStaff() throws Exception {
        String key = key();
        assertThat(deposit(aliceToken, key, source, "20", "USD").statusCode()).isEqualTo(403);
        var first = deposit(staffToken, key, source, "20", "USD");
        var replay = deposit(staffToken, key, source, "20", "USD");
        assertThat(first.statusCode()).isEqualTo(200);
        assertThat(body(replay).path("data")).isEqualTo(body(first).path("data"));
        balance(source, "120.00");
        assertThat(deposit(staffToken, key(), source, "20", "KHR").statusCode()).isEqualTo(400);
        balance(source, "120.00");
    }

    @Test void invalidMoneyAndAccountsNeverChangeBalances() throws Exception {
        for (String amount : List.of("0", "-1", "0.001", "10000000000000"))
            assertThat(transfer(aliceToken, key(), source, destination, amount, "USD").statusCode()).isEqualTo(400);
        assertThat(transfer(aliceToken, null, source, destination, "1", "USD").statusCode()).isEqualTo(400);
        assertThat(transfer(aliceToken, "bad key", source, destination, "1", "USD").statusCode()).isEqualTo(400);
        assertThat(transfer(aliceToken, key(), source, destination, "1", "EUR").statusCode()).isEqualTo(400);
        assertThat(transfer(aliceToken, key(), source, source, "1", "USD").statusCode()).isEqualTo(400);
        assertThat(transfer(aliceToken, key(), destination, source, "1", "USD").statusCode()).isEqualTo(404);
        jdbc.update("update accounts set status = 'FROZEN' where id = ?", destination.getId());
        assertThat(transfer(aliceToken, key(), source, destination, "1", "USD").statusCode()).isEqualTo(409);
        balance(source, "100.00"); balance(destination, "0.00");
        assertThat(postings()).isZero();
    }

    @Test void khrUsesWholeRielAndReplaysTheSameResult() throws Exception {
        var from = account(alice, "KHR", "1000"); var to = account(bob, "KHR", "0");
        assertThat(transfer(aliceToken, key(), from, to, "1.5", "KHR").statusCode()).isEqualTo(400);
        String key = key();
        var first = transfer(aliceToken, key, from, to, "250", "KHR");
        var replay = transfer(aliceToken, key, from, to, "250.00", "KHR");
        assertThat(first.statusCode()).isEqualTo(200);
        assertThat(body(first).path("data")).isEqualTo(body(replay).path("data"));
        balance(from, "750"); balance(to, "250");
    }

    @Test void auditFailureRollsBackBalancesTransactionAndClaimThenAllowsRetry() throws Exception {
        String key = key();
        jdbc.execute("alter table audit_logs add constraint test_reject_transfer_audit check (action <> 'TRANSFER' or not success) not valid");
        try {
            assertThat(transfer(aliceToken, key, source, destination, "20", "USD").statusCode()).isEqualTo(503);
            balance(source, "100.00"); balance(destination, "0.00");
            assertThat(postings()).isZero();
            assertThat(jdbc.queryForObject("select count(*) from idempotency_records where request_key=?", Integer.class, key)).isZero();
            assertThat(jdbc.queryForObject("select count(*) from audit_logs where action='TRANSFER' and not success and performer_user_id=?", Integer.class, alice.getId().toString())).isPositive();
        } finally {
            jdbc.execute("alter table audit_logs drop constraint test_reject_transfer_audit");
        }
        assertThat(transfer(aliceToken, key, source, destination, "20", "USD").statusCode()).isEqualTo(200);
        balance(source, "80.00"); balance(destination, "20.00");
    }

    @Test void transferRechecksAFrozenAccountAfterWaitingForItsLock() throws Exception {
        try (var connection = DriverManager.getConnection(POSTGRES.getJdbcUrl("postgres", "postgres"), "postgres", "postgres");
             var statement = connection.createStatement()) {
            connection.setAutoCommit(false);
            statement.execute("update accounts set status='FROZEN' where id=" + source.getId());
            try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
                var result = executor.submit(() -> transfer(aliceToken, key(), source, destination, "20", "USD"));
                awaitLock(statement);
                connection.commit();
                assertThat(result.get(15, TimeUnit.SECONDS).statusCode()).isEqualTo(409);
            } finally { connection.rollback(); }
        }
        balance(source, "100.00"); balance(destination, "0.00");
    }

    @Test void staffStatusChangeDoesNotOverwriteAnIncomingBalanceChange() throws Exception {
        try (var connection = DriverManager.getConnection(POSTGRES.getJdbcUrl("postgres", "postgres"), "postgres", "postgres");
             var statement = connection.createStatement()) {
            connection.setAutoCommit(false);
            statement.execute("update accounts set balance=200 where id=" + source.getId());
            try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
                var result = executor.submit(() -> call("PATCH", "/accounts/"+source.getAccountNumber()+"/status", staffToken, null, Map.of("status", "FROZEN")));
                awaitLock(statement);
                connection.commit();
                assertThat(result.get(15, TimeUnit.SECONDS).statusCode()).isEqualTo(200);
            } finally { connection.rollback(); }
        }
        balance(source, "200.00");
        assertThat(accounts.findById(source.getId()).orElseThrow().getStatus()).isEqualTo(AccountStatus.FROZEN);
    }

    @Test void historyPaginationIsBoundedAndStableForEqualTimestamps() throws Exception {
        for (int i=0;i<5;i++) jdbc.update("""
                insert into transactions(reference_number, source_account_id, destination_account_id, amount, fee, currency, transaction_type, status, created_at)
                values (?, ?, ?, 1, 0, 'USD', 'TRANSFER', 'SUCCESS', '2026-10-01T00:00:00Z')
                """, "TEST-"+UUID.randomUUID().toString().replace("-", "").substring(0,30), source.getId(), destination.getId());
        String path = "/transactions/account/"+source.getAccountNumber();
        var first = body(call("GET", path+"?page=0&size=2", aliceToken, null, null)).path("data");
        var second = body(call("GET", path+"?page=1&size=2", aliceToken, null, null)).path("data");
        assertThat(first.path("content").size()).isEqualTo(2);
        assertThat(first.path("content").get(1).path("id").asLong()).isGreaterThan(second.path("content").get(0).path("id").asLong());
        for (String query : List.of("?page=-1", "?size=0", "?size=101", "?page=2147483647&size=100"))
            assertThat(call("GET", path+query, aliceToken, null, null).statusCode()).isEqualTo(400);
        assertThat(call("GET", "/accounts/me?size=101", aliceToken, null, null).statusCode()).isEqualTo(400);
    }

    @Test void auditEventsHaveTheActorCorrelationAndNoFinancialPayload() throws Exception {
        var response = transfer(aliceToken, key(), source, destination, "10", "USD");
        String reference = body(response).path("data").path("referenceNumber").asText();
        var event = jdbc.queryForMap("select * from audit_logs where action='TRANSFER' and target_resource_id=?", reference);
        assertThat(event.get("performer_user_id")).isEqualTo(alice.getId().toString());
        assertThat(event.get("correlation_id")).isEqualTo(response.headers().firstValue("X-Correlation-ID").orElseThrow());
        assertThat(event.get("correlation_id")).isEqualTo(jdbc.queryForObject("select correlation_id from transactions where reference_number=?", String.class, reference));
        assertThat(event.get("details")).isEqualTo("COMPLETED");
        var denied = call("POST", "/auth/login", null, null, Map.of("usernameOrEmail", "nobody@example.test", "password", PASSWORD,
                "otpCode", "123456", "deviceFingerprint", key(), "deviceName", "Test"));
        assertThat(denied.statusCode()).isEqualTo(401);
        var failure = jdbc.queryForMap("select * from audit_logs where correlation_id=?", denied.headers().firstValue("X-Correlation-ID").orElseThrow());
        assertThat(failure.get("performer_user_id")).isEqualTo("ANONYMOUS");
        assertThat(failure.toString()).doesNotContain(PASSWORD, "123456", "nobody@example.test");
    }

    @Test void serviceBoundaryAndDatabaseConstraintsRejectInvalidMoney() {
        var request = new TransferRequestDto(); request.setSourceAccountNumber(source.getAccountNumber());
        request.setDestinationAccountNumber(destination.getAccountNumber()); request.setCurrency("USD"); request.setAmount(new BigDecimal("-1"));
        assertThatThrownBy(() -> service.processTransfer(alice, request, key())).isInstanceOf(com.bank.digital_banking.common.exception.ApiException.class);
        assertThatThrownBy(() -> jdbc.update("update accounts set balance=-1 where id=?", source.getId())).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        assertThatThrownBy(() -> jdbc.update("update accounts set currency='EUR' where id=?", source.getId())).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        balance(source, "100.00");
    }

    @Test void aDestinationOverflowRollsBackTheDebitAndIdempotencyClaim() throws Exception {
        jdbc.update("update accounts set balance=9999999999999.99 where id=?", destination.getId());
        String key = key();
        assertThat(transfer(aliceToken, key, source, destination, "1", "USD").statusCode()).isEqualTo(400);
        balance(source, "100.00"); balance(destination, "9999999999999.99");
        assertThat(postings()).isZero();
        assertThat(jdbc.queryForObject("select count(*) from idempotency_records where request_key=?", Integer.class, key)).isZero();
    }

    @Test void allListEndpointsApplyBoundsAndPreserveTheirResponseShapes() throws Exception {
        String admin = token(users.findByUsername("admin.demo").orElseThrow());
        User merchant = users.findByUsername("merchant.demo").orElseThrow();
        String merchantToken = token(merchant);
        for (var entry : List.of(
                Map.entry("/accounts/me", aliceToken), Map.entry("/audit/module/TRANSACTION", admin),
                Map.entry("/fraud/flagged", staffToken), Map.entry("/merchants/owner/"+merchant.getId(), merchantToken),
                Map.entry("/merchants/status/PENDING", admin), Map.entry("/ai/insights/user/"+alice.getId(), aliceToken))) {
            var result = call("GET", entry.getKey()+"?page=0&size=2", entry.getValue(), null, null);
            assertThat(result.statusCode()).as(result.body()).isEqualTo(200);
            var list = body(result); if (entry.getKey().equals("/accounts/me")) list = list.path("data");
            assertThat(list.isArray()).isTrue(); assertThat(list.size()).isLessThanOrEqualTo(2);
            assertThat(call("GET", entry.getKey()+"?size=101", entry.getValue(), null, null).statusCode()).isEqualTo(400);
        }
    }

    @Test void realAuthenticationAccountAndAdministrativeActionsEmitAudits() throws Exception {
        assertThat(call("POST", "/auth/request-otp", null, null, Map.of("email", alice.getEmail(), "purpose", "LOGIN")).statusCode()).isEqualTo(200);
        var login = call("POST", "/auth/login", null, null, Map.of("usernameOrEmail", alice.getEmail(), "password", PASSWORD,
                "otpCode", SMTP.code(alice.getEmail()), "deviceFingerprint", key(), "deviceName", "Audit test"));
        assertThat(login.statusCode()).as(login.body()).isEqualTo(200);
        assertAudit(login, "LOGIN", alice.getId());
        var data = body(login).path("data");
        var refresh = call("POST", "/auth/refresh", null, null, Map.of("refreshToken", data.path("refreshToken").asText()));
        assertThat(refresh.statusCode()).isEqualTo(200); assertAudit(refresh, "REFRESH", alice.getId());
        String access = body(refresh).path("data").path("accessToken").asText();
        var created = call("POST", "/accounts", access, null, Map.of("accountType", "SAVINGS", "currency", "USD", "initialDeposit", 0));
        assertThat(created.statusCode()).isEqualTo(201); assertAudit(created, "ACCOUNT_CREATED", alice.getId());
        User admin = users.findByUsername("admin.demo").orElseThrow();
        var frozen = call("PATCH", "/accounts/"+source.getAccountNumber()+"/status", token(admin), null, Map.of("status", "FROZEN"));
        assertThat(frozen.statusCode()).isEqualTo(200); assertAudit(frozen, "ACCOUNT_STATUS_CHANGED", admin.getId());
        var logout = call("POST", "/auth/logout", access, null, null);
        assertThat(logout.statusCode()).isEqualTo(200); assertAudit(logout, "LOGOUT", alice.getId());
    }

    @Test void manualAuditSubmissionsCannotFabricateFinancialEventsOrActors() throws Exception {
        User admin = users.findByUsername("admin.demo").orElseThrow();
        var response = call("POST", "/audit/log", token(admin), null, Map.of("moduleName", "TRANSACTION", "action", "TRANSFER",
                "performerUserId", "someone-else", "details", PASSWORD, "ipAddress", "invented", "success", true));
        assertThat(response.statusCode()).isEqualTo(202);
        var event = jdbc.queryForMap("select * from audit_logs where correlation_id=?", response.headers().firstValue("X-Correlation-ID").orElseThrow());
        assertThat(event.get("module_name")).isEqualTo("AUDIT");
        assertThat(event.get("action")).isEqualTo("MANUAL_EVENT_SUBMITTED");
        assertThat(event.get("performer_user_id")).isEqualTo(admin.getId().toString());
        assertThat(event.toString()).doesNotContain(PASSWORD, "someone-else", "invented");
    }

    void assertAudit(HttpResponse<String> response, String action, Long actor) {
        var event = jdbc.queryForMap("select * from audit_logs where correlation_id=? and action=?",
                response.headers().firstValue("X-Correlation-ID").orElseThrow(), action);
        assertThat(event.get("performer_user_id")).isEqualTo(actor.toString());
        assertThat(event.get("success")).isEqualTo(true);
    }

    Account account(User owner, String currency, String balance) {
        return accounts.save(Account.builder().user(owner).accountNumber(Long.toString(NUMBERS.incrementAndGet()))
                .accountType(AccountType.SAVINGS).currency(currency).balance(new BigDecimal(balance)).status(AccountStatus.ACTIVE).build());
    }
    String token(User user) {
        var device = devices.save(Device.builder().user(user).deviceFingerprint(key()).deviceName("Phase 1 test").status(DeviceStatus.ACTIVE).build());
        return sessions.create(user, device).getAccessToken();
    }
    String key() { return UUID.randomUUID().toString(); }
    void balance(Account account, String expected) { assertThat(accounts.findById(account.getId()).orElseThrow().getBalance()).isEqualByComparingTo(expected); }
    int postings() { return jdbc.queryForObject("select count(*) from transactions where source_account_id=?", Integer.class, source.getId()); }
    JsonNode body(HttpResponse<String> response) { return json.readTree(response.body()); }
    HttpResponse<String> transfer(String token, String key, Account from, Account to, String amount, String currency) throws Exception {
        return call("POST", "/transactions/transfer", token, key, Map.of("sourceAccountNumber", from.getAccountNumber(), "destinationAccountNumber", to.getAccountNumber(), "amount", new BigDecimal(amount), "currency", currency));
    }
    HttpResponse<String> deposit(String token, String key, Account to, String amount, String currency) throws Exception {
        return call("POST", "/transactions/deposit", token, key, Map.of("accountNumber", to.getAccountNumber(), "amount", new BigDecimal(amount), "currency", currency));
    }
    HttpResponse<String> call(String method, String path, String token, String key, Object data) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://localhost:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(20));
        if (token != null) request.header("Authorization", "Bearer "+token);
        if (key != null) request.header("Idempotency-Key", key);
        if (data != null) request.header("Content-Type", "application/json");
        return client.send(request.method(method, data == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(data))).build(), HttpResponse.BodyHandlers.ofString());
    }
    List<HttpResponse<String>> parallel(Callable<HttpResponse<String>> first, Callable<HttpResponse<String>> second) throws Exception {
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            var ready = new CountDownLatch(2); var start = new CountDownLatch(1);
            var a = executor.submit(() -> { ready.countDown(); start.await(); return first.call(); });
            var b = executor.submit(() -> { ready.countDown(); start.await(); return second.call(); });
            assertThat(ready.await(5, TimeUnit.SECONDS)).isTrue(); start.countDown();
            return List.of(a.get(25, TimeUnit.SECONDS), b.get(25, TimeUnit.SECONDS));
        }
    }
    void awaitLock(java.sql.Statement statement) throws Exception {
        org.awaitility.Awaitility.await().pollInSameThread().atMost(Duration.ofSeconds(5)).until(() -> {
            statement.execute("select pg_stat_clear_snapshot()");
            try (var rows = statement.executeQuery("select count(*) from pg_stat_activity where datname=current_database() and wait_event_type='Lock' and pid <> pg_backend_pid()")) {
                rows.next(); return rows.getInt(1)>0;
            }
        });
    }
}
