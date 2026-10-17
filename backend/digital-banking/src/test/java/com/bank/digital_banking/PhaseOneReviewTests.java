package com.bank.digital_banking;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.account.entity.*;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.service.SessionService;
import com.bank.digital_banking.module.transaction.entity.TransactionType;
import com.bank.digital_banking.module.transaction.service.FinancialCommandService;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
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

@TestPropertySource(properties = {"app.financial.lock-timeout-ms=250", "app.cors.allowed-origins=http://localhost:8081"})
class PhaseOneReviewTests extends PostgresIntegrationTest {
    @Value("${local.server.port}") int port;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper json;
    @Autowired UserRepository users;
    @Autowired DeviceRepository devices;
    @Autowired AccountRepository accounts;
    @Autowired SessionService sessions;
    @Autowired FinancialCommandService commands;
    @Autowired EntityManager entities;
    @Autowired PlatformTransactionManager transactionManager;
    @Autowired com.bank.digital_banking.module.account.service.AccountService accountService;
    @Autowired javax.sql.DataSource dataSource;
    static final AtomicLong NUMBERS = new AtomicLong(6000000000L);
    final HttpClient client = HttpClient.newHttpClient();
    User alice, bob;
    Account source, destination;
    String token;

    @BeforeEach void setup() {
        alice = users.findByUsername("alice.demo").orElseThrow();
        bob = users.findByUsername("bob.demo").orElseThrow();
        source = account(alice, "100"); destination = account(bob, "0");
        var device = devices.save(Device.builder().user(alice).deviceName("Review test").deviceFingerprint(key()).build());
        token = sessions.create(alice, device).getAccessToken();
    }

    @Test void aPreloadedAccountMustNotOverwriteANewerCommittedBalance() {
        new TransactionTemplate(transactionManager).execute(status -> {
            assertThat(entities.find(Account.class, source.getId()).getBalance()).isEqualByComparingTo("100");
            externalUpdate("update accounts set balance=200 where id="+source.getId());
            commands.execute(alice, TransactionType.TRANSFER, key(), source.getAccountNumber(), destination.getAccountNumber(), BigDecimal.TEN, "USD", null);
            return null;
        });
        balance(source, "190"); balance(destination, "10");
    }

    @Test void aPreloadedAccountMustNotBypassACommittedFreeze() {
        assertThatThrownBy(() -> new TransactionTemplate(transactionManager).execute(status -> {
            entities.find(Account.class, source.getId());
            externalUpdate("update accounts set status='FROZEN' where id="+source.getId());
            return commands.execute(alice, TransactionType.TRANSFER, key(), source.getAccountNumber(), destination.getAccountNumber(), BigDecimal.TEN, "USD", null);
        })).isInstanceOf(ApiException.class).hasMessageContaining("not active");
        balance(source, "100"); balance(destination, "0");
    }

    @Test void databaseRejectsNotANumberBalances() {
        try {
            assertThatThrownBy(() -> jdbc.update("update accounts set balance='NaN'::numeric where id=?", source.getId()))
                    .isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        } finally { jdbc.update("update accounts set balance=100 where id=?", source.getId()); }
    }

    @Test void databaseRejectsNotANumberTransactionAmountsAndFees() {
        String reference = "QA-"+key().replace("-", "");
        try {
            assertThatThrownBy(() -> jdbc.update("""
                    insert into transactions(reference_number,destination_account_id,amount,fee,currency,transaction_type,status)
                    values(?,?,'NaN'::numeric,0,'USD','DEPOSIT','SUCCESS')
                    """, reference, destination.getId())).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
            assertThatThrownBy(() -> jdbc.update("""
                    insert into transactions(reference_number,destination_account_id,amount,fee,currency,transaction_type,status)
                    values(?,?,1,'NaN'::numeric,'USD','DEPOSIT','SUCCESS')
                    """, reference, destination.getId())).isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        } finally { jdbc.update("delete from transactions where reference_number=?", reference); }
    }

    @Test void totalAuditStorageFailureReturnsAStructuredUnavailableResponseWithoutPosting() throws Exception {
        HttpResponse<String> anonymous, financial;
        String key = key();
        jdbc.execute("alter table audit_logs add constraint qa_audit_unavailable check(false) not valid");
        try {
            anonymous = call("GET", "/accounts/me", null, null, null);
            financial = transfer(key);
        } finally { jdbc.execute("alter table audit_logs drop constraint qa_audit_unavailable"); }
        balance(source, "100"); balance(destination, "0");
        assertThat(jdbc.queryForObject("select count(*) from idempotency_records where request_key=?", Integer.class, key)).isZero();
        for (var response : List.of(anonymous, financial)) {
            assertThat(response.statusCode()).as(response.body()).isEqualTo(503);
            var body = json.readTree(response.body());
            assertThat(body.path("error").asText()).isEqualTo("AUDIT_UNAVAILABLE");
            assertThat(body.path("success").asBoolean(true)).isFalse();
            assertThat(response.headers().firstValue("X-Correlation-ID")).isPresent();
            assertThat(response.headers().firstValue("Access-Control-Allow-Origin")).contains("http://localhost:8081");
            assertThat(response.body()).doesNotContain("audit_logs", "qa_audit_unavailable", "SQLException");
        }
        assertThat(transfer(key).statusCode()).isEqualTo(200);
    }

    @Test void validationRejectionsUseTheSameAuditModuleAsSuccessfulTransfers() throws Exception {
        var response = call("POST", "/transactions/transfer", token, key(), Map.of("sourceAccountNumber", source.getAccountNumber(),
                "destinationAccountNumber", destination.getAccountNumber(), "amount", new BigDecimal("0.001"), "currency", "USD"));
        assertThat(response.statusCode()).isEqualTo(400);
        var event = jdbc.queryForMap("select * from audit_logs where correlation_id=?", response.headers().firstValue("X-Correlation-ID").orElseThrow());
        assertThat(event.get("module_name")).isEqualTo("TRANSACTION");
        assertThat(event.get("action")).isEqualTo("TRANSFER");
    }

    @Test void rolledBackRegistrationDoesNotAttributeFailureToANonexistentUser() throws Exception {
        String username = "qa."+key().substring(0,8), email = username+"@example.test";
        assertThat(call("POST", "/auth/request-otp", null, null, Map.of("email",email,"purpose","SIGNUP")).statusCode()).isEqualTo(200);
        jdbc.execute("alter table audit_logs add constraint qa_registration_audit_failure check(action<>'REGISTER' or not success) not valid");
        HttpResponse<String> response;
        try {
            response = call("POST", "/auth/register", null, null, Map.of("username",username,"email",email,"password",PASSWORD,
                    "otpCode",SMTP.code(email),"deviceFingerprint",key(),"deviceName","Review registration"));
        } finally { jdbc.execute("alter table audit_logs drop constraint qa_registration_audit_failure"); }
        assertThat(response.statusCode()).isEqualTo(503);
        assertThat(users.findByEmail(email)).isEmpty();
        var event = jdbc.queryForMap("select * from audit_logs where correlation_id=?", response.headers().firstValue("X-Correlation-ID").orElseThrow());
        assertThat(event.get("performer_user_id")).isEqualTo("ANONYMOUS");
    }

    @Test void lockContentionHasABoundedResponseAndLeavesNoClaimOrPosting() throws Exception {
        try (var connection = DriverManager.getConnection(POSTGRES.getJdbcUrl("postgres", "postgres"), "postgres", "postgres");
             var sql = connection.createStatement(); var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            connection.setAutoCommit(false);
            sql.execute("select id from accounts where id="+source.getId()+" for update");
            String key = key();
            var future = executor.submit(() -> transfer(key));
            HttpResponse<String> response = null;
            boolean timedOut = false;
            try { response = future.get(2, TimeUnit.SECONDS); }
            catch (TimeoutException ex) { timedOut = true; }
            finally { connection.rollback(); }
            future.get(10, TimeUnit.SECONDS);
            assertThat(timedOut).as("Account locks must respect the configured 250ms limit").isFalse();
            assertThat(response.statusCode()).isEqualTo(409);
            assertThat(json.readTree(response.body()).path("error").asText()).isEqualTo("CONCURRENT_UPDATE");
            balance(source,"100"); balance(destination,"0");
            assertThat(jdbc.queryForObject("select count(*) from idempotency_records where request_key=?",Integer.class,key)).isZero();
        }
    }

    @Test void staffStatusChangesRefreshPreloadedBalances() {
        var staff = users.findByUsername("employee.demo").orElseThrow();
        new TransactionTemplate(transactionManager).execute(status -> {
            entities.find(Account.class, source.getId());
            externalUpdate("update accounts set balance=200 where id="+source.getId());
            var change = new com.bank.digital_banking.module.account.dto.UpdateAccountStatusDto();
            change.setStatus(AccountStatus.FROZEN);
            accountService.updateAccountStatus(staff, source.getAccountNumber(), change);
            return null;
        });
        balance(source, "200");
        assertThat(accounts.findById(source.getId()).orElseThrow().getStatus()).isEqualTo(AccountStatus.FROZEN);
    }

    @Test void anInFlightIdempotencyClaimHasTheSameBoundedWaitAndCanBeRetried() throws Exception {
        String key = key();
        try (var connection = DriverManager.getConnection(POSTGRES.getJdbcUrl("postgres", "postgres"), "postgres", "postgres");
             var sql = connection.prepareStatement("insert into idempotency_records(actor_user_id,operation,request_key,request_hash) values(?,'TRANSFER',?,repeat('a',64))")) {
            connection.setAutoCommit(false);
            sql.setLong(1, alice.getId()); sql.setString(2,key); sql.executeUpdate();
            var response = transfer(key);
            assertThat(response.statusCode()).as(response.body()).isEqualTo(409);
            assertThat(json.readTree(response.body()).path("error").asText()).isEqualTo("CONCURRENT_UPDATE");
            connection.rollback();
        }
        balance(source,"100"); balance(destination,"0");
        assertThat(transfer(key).statusCode()).isEqualTo(200);
        balance(source,"90"); balance(destination,"10");
    }

    @Test void theFinancialLockTimeoutDoesNotLeakIntoPooledConnections() throws Exception {
        assertThat(transfer(key()).statusCode()).isEqualTo(200);
        try (var first=dataSource.getConnection(); var second=dataSource.getConnection()) {
            for (var connection : List.of(first,second)) {
                try (var sql=connection.createStatement(); var rows=sql.executeQuery("show lock_timeout")) {
                    rows.next(); assertThat(rows.getString(1)).isEqualTo("0");
                }
            }
        }
    }

    @Test void simultaneousDifferentPayloadsCannotShareOneSuccessfulKey() throws Exception {
        String key=key();
        try (var executor=Executors.newVirtualThreadPerTaskExecutor()) {
            var start=new CountDownLatch(1);
            var first=executor.submit(() -> { start.await(); return transfer(key); });
            var second=executor.submit(() -> { start.await(); return call("POST","/transactions/transfer",token,key,
                    Map.of("sourceAccountNumber",source.getAccountNumber(),"destinationAccountNumber",destination.getAccountNumber(),"amount",20,"currency","USD")); });
            start.countDown();
            var responses=List.of(first.get(10,TimeUnit.SECONDS),second.get(10,TimeUnit.SECONDS));
            assertThat(responses).extracting(HttpResponse::statusCode).containsExactlyInAnyOrder(200,409);
            var conflict=responses.stream().filter(r -> r.statusCode()==409).findFirst().orElseThrow();
            assertThat(json.readTree(conflict.body()).path("error").asText()).isEqualTo("IDEMPOTENCY_CONFLICT");
            assertThat(jdbc.queryForObject("select count(*) from transactions where source_account_id=?",Integer.class,source.getId())).isEqualTo(1);
        }
    }

    @Test void aLockedAuditTableCannotLeaveTheFailureAuditWaitingForever() throws Exception {
        try (var connection=DriverManager.getConnection(POSTGRES.getJdbcUrl("postgres","postgres"),"postgres","postgres");
             var sql=connection.createStatement(); var executor=Executors.newVirtualThreadPerTaskExecutor()) {
            connection.setAutoCommit(false);
            sql.execute("lock table audit_logs in access exclusive mode");
            var future=executor.submit(() -> transfer(key()));
            HttpResponse<String> response=null; boolean timedOut=false;
            try { response=future.get(2,TimeUnit.SECONDS); }
            catch(TimeoutException ex) { timedOut=true; }
            finally { connection.rollback(); }
            future.get(10,TimeUnit.SECONDS);
            assertThat(timedOut).as("Failure auditing also needs a bounded lock wait").isFalse();
            assertThat(response.statusCode()).isEqualTo(503);
            assertThat(json.readTree(response.body()).path("error").asText()).isEqualTo("AUDIT_UNAVAILABLE");
            balance(source,"100"); balance(destination,"0");
        }
    }

    Account account(User owner, String balance) {
        return accounts.save(Account.builder().user(owner).accountNumber(Long.toString(NUMBERS.incrementAndGet()))
                .accountType(AccountType.SAVINGS).currency("USD").balance(new BigDecimal(balance)).build());
    }
    void externalUpdate(String statement) {
        try (var connection = DriverManager.getConnection(POSTGRES.getJdbcUrl("postgres", "postgres"), "postgres", "postgres"); var sql = connection.createStatement()) { sql.execute(statement); }
        catch (Exception ex) { throw new IllegalStateException(ex); }
    }
    void balance(Account account, String expected) { assertThat(accounts.findById(account.getId()).orElseThrow().getBalance()).isEqualByComparingTo(expected); }
    String key() { return UUID.randomUUID().toString(); }
    HttpResponse<String> transfer(String key) throws Exception {
        return call("POST","/transactions/transfer",token,key,Map.of("sourceAccountNumber",source.getAccountNumber(),"destinationAccountNumber",destination.getAccountNumber(),"amount",10,"currency","USD"));
    }
    HttpResponse<String> call(String method, String path, String token, String key, Object data) throws Exception {
        var request=HttpRequest.newBuilder(URI.create("http://localhost:"+port+"/api/v1"+path)).timeout(Duration.ofSeconds(15));
        request.header("Origin","http://localhost:8081");
        if(token!=null)request.header("Authorization","Bearer "+token);
        if(key!=null)request.header("Idempotency-Key",key);
        if(data!=null)request.header("Content-Type","application/json");
        return client.send(request.method(method,data==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(json.writeValueAsString(data))).build(),HttpResponse.BodyHandlers.ofString());
    }
}
