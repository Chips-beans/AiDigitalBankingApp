package com.bank.digital_banking;

import com.bank.digital_banking.module.account.service.AccountService;
import com.bank.digital_banking.module.auth.dto.TokenResponseDto;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.service.*;
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

/**
 * M8 over HTTP: a shop owner moves money from a business wallet to their own personal wallet.
 * Only a fresh-PIN approval in the Customer App moves it. Same context as the other Merchant tests.
 */
@SpringBootTest(classes = DigitalBankingApplication.class, webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "app.dev.opening-funding.enabled=true")
class MerchantOwnerTransferTests extends PostgresIntegrationTest {
    static final String PIN = "0427";
    @Value("${local.server.port}") int port;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired UserRepository users;
    @Autowired RoleRepository roles;
    @Autowired SessionService sessions;
    @Autowired DeviceService devices;
    @Autowired AccountService accounts;
    @Autowired PlatformTransactionManager txManager;
    final HttpClient http = HttpClient.newHttpClient();
    /** personalUsd/personalKhr are null for an owner who never opened personal wallets. */
    record Owner(long id, String merchant, String customer, String code, String khr, String usd,
                 String personalUsd, String personalKhr) {}

    @BeforeEach void limits() { jdbc.update("DELETE FROM merchant_auth_limits"); }

    @Test void usdAndKhrTransfersMoveExactlyOnceAndAreNotSales() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "50.00"); setBalance(owner.khr(), "100000");

        var created = create(owner, key(), owner.usd(), "12.50");
        assertThat(created.statusCode()).as(created.body()).isEqualTo(201);
        var intent = data(created);
        assertThat(intent.path("status").asText()).isEqualTo("PENDING");
        assertThat(intent.path("approvalUri").asText()).startsWith("kesorbank://merchant/transfer?intentId=" + intent.path("intentId").asText() + "&handoffToken=");
        assertThat(intent.path("destinationAccount").asText()).isEqualTo("•••• " + owner.personalUsd().substring(owner.personalUsd().length() - 4));
        assertThat(intent.toString()).doesNotContain(owner.personalUsd());
        assertThat(intent.path("amount").asText()).isEqualTo("12.50");
        String id = intent.path("intentId").asText(), handoff = handoff(intent);

        var details = data(call("GET", "/merchant-transfers/" + id, owner.customer(), null, Map.of("X-Merchant-Handoff", handoff)));
        assertThat(details.path("shopName").asText()).isEqualTo("Sokha Coffee");
        assertThat(details.path("amount").asText()).isEqualTo("12.50");
        assertThat(details.path("sourceAccount").asText()).startsWith("••••");
        assertThat(details.path("destinationAccount").asText()).startsWith("••••");

        var approved = approve(owner, id, handoff, PIN);
        assertThat(approved.statusCode()).as(approved.body()).isEqualTo(200);
        var outcome = data(approved);
        assertThat(outcome.path("status").asText()).isEqualTo("COMPLETED");
        assertThat(outcome.path("callbackUri").asText()).startsWith("kesormerchant://transfer/callback?intentId=" + id + "&state=");
        assertThat(outcome.path("callbackUri").asText()).doesNotContain("error=");
        assertThat(balance(owner.usd())).isEqualByComparingTo("37.50");
        assertThat(balance(owner.personalUsd())).isEqualByComparingTo("212.50");
        assertThat(transfersOf(owner)).isEqualTo(1);

        var status = data(call("GET", "/merchants/me/owner-transfers/" + id, owner.merchant(), null));
        assertThat(status.path("status").asText()).isEqualTo("COMPLETED");
        assertThat(status.path("receipt").path("reference").asText()).startsWith("TXN-");
        assertThat(status.path("approvalUri").isNull()).isTrue();

        // KHR: whole riel, same rules.
        var khr = data(create(owner, key(), owner.khr(), "25000"));
        assertThat(data(approve(owner, khr.path("intentId").asText(), handoff(khr), PIN)).path("status").asText()).isEqualTo("COMPLETED");
        assertThat(balance(owner.khr())).isEqualByComparingTo("75000");
        assertThat(balance(owner.personalKhr())).isEqualByComparingTo("125000");

        // Not a sale; it is wallet activity out of the business wallet and an incoming transfer for the owner.
        var sales = data(call("GET", "/merchants/me/sales?from=2000-01-01&to=2099-12-31", owner.merchant(), null));
        assertThat(sales.path("items")).isEmpty();
        var wallet = data(call("GET", "/merchants/me/wallets/" + owner.usd(), owner.merchant(), null));
        assertThat(wallet.path("activity").get(0).path("kind").asText()).isEqualTo("TRANSFER_OUT");
        assertThat(wallet.path("activity").get(0).path("direction").asText()).isEqualTo("OUT");
        assertThat(wallet.path("activity").get(0).path("amount").asText()).isEqualTo("12.50");
        var history = data(call("GET", "/transactions/account/" + owner.personalUsd(), owner.customer(), null)).path("content");
        assertThat(history.get(0).path("operation").asText()).isEqualTo("OWNER_TRANSFER");
        assertThat(history.get(0).path("sourceName").asText()).isEqualTo("Sokha Coffee");
        assertThat(collections(owner)).isZero();
    }

    @Test void theDestinationIsNeverChosenByTheClient() throws Exception {
        var owner = owner(true); var other = owner(true);
        setBalance(owner.usd(), "50.00");
        assertThat(create(owner, key(), Map.of("sourceAccountNumber", owner.usd(), "amount", "5.00",
                "destinationAccountNumber", other.personalUsd())).statusCode()).isEqualTo(400);
        assertThat(create(owner, key(), Map.of("sourceAccountNumber", owner.usd(), "amount", "5.00",
                "currency", "USD")).statusCode()).isEqualTo(400);
        // Personal and foreign wallets are never valid sources.
        assertThat(create(owner, key(), owner.personalUsd(), "5.00").statusCode()).isEqualTo(404);
        assertThat(create(owner, key(), other.usd(), "5.00").statusCode()).isEqualTo(404);
        assertThat(create(owner, key(), owner.usd(), "0").statusCode()).isEqualTo(400);
        assertThat(error(create(owner, key(), owner.khr(), "10.5"))).isEqualTo("INVALID_AMOUNT");
        assertThat(error(call("POST", "/merchants/me/owner-transfers", owner.merchant(),
                Map.of("sourceAccountNumber", owner.usd(), "amount", "1.00")))).isEqualTo("IDEMPOTENCY_KEY_REQUIRED");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_owner_transfers WHERE owner_user_id IN (?,?)", Long.class,
                owner.id(), other.id())).isZero();
    }

    @Test void anOwnerWithoutAPersonalWalletInThatCurrencyIsToldToOpenOne() throws Exception {
        var owner = owner(false);
        setBalance(owner.usd(), "10.00");
        var response = create(owner, key(), owner.usd(), "5.00");
        assertThat(response.statusCode()).isEqualTo(409);
        assertThat(error(response)).isEqualTo("OWNER_WALLET_REQUIRED");
        assertThat(json.readTree(response.body()).path("message").asText()).contains("Kesor Bank");
        assertThat(balance(owner.usd())).isEqualByComparingTo("10.00");
    }

    @Test void amountsAboveTheBalanceAreRefusedUpFront() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "5.00");
        assertThat(error(create(owner, key(), owner.usd(), "5.01"))).isEqualTo("INSUFFICIENT_FUNDS");
        assertThat(create(owner, key(), owner.usd(), "5.00").statusCode()).isEqualTo(201);
    }

    @Test void wrongPinsShareTheBudgetAndMoveNoMoney() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "20.00");
        var intent = data(create(owner, key(), owner.usd(), "4.00"));
        String id = intent.path("intentId").asText(), handoff = handoff(intent);

        var wrong = approve(owner, id, handoff, "1111");
        assertThat(wrong.statusCode()).isEqualTo(403);
        assertThat(error(wrong)).isEqualTo("PIN_INVALID");
        assertThat(failures(owner)).isEqualTo(1);
        assertThat(balance(owner.usd())).isEqualByComparingTo("20.00");
        assertThat(statusOf(id)).isEqualTo("PENDING");

        assertThat(data(approve(owner, id, handoff, PIN)).path("status").asText()).isEqualTo("COMPLETED");
        assertThat(failures(owner)).isZero();

        setBalance(owner.usd(), "20.00");
        var second = data(create(owner, key(), owner.usd(), "4.00"));
        for (int attempt = 1; attempt <= 4; attempt++)
            assertThat(error(approve(owner, second.path("intentId").asText(), handoff(second), "1111"))).isEqualTo("PIN_INVALID");
        assertThat(error(approve(owner, second.path("intentId").asText(), handoff(second), "1111"))).isEqualTo("PIN_RECOVERY_REQUIRED");
        assertThat(failures(owner)).isEqualTo(5);
        var locked = approve(owner, second.path("intentId").asText(), handoff(second), PIN);
        assertThat(locked.statusCode()).isEqualTo(403);
        assertThat(statusOf(second.path("intentId").asText())).isEqualTo("PENDING");
        assertThat(balance(owner.usd())).isEqualByComparingTo("20.00");
        assertThat(transfersOf(owner)).isEqualTo(1);
    }

    @Test void wrongTokensWrongPeopleAndWrongSessionTypesAreRejected() throws Exception {
        var owner = owner(true); var stranger = owner(true);
        setBalance(owner.usd(), "20.00");
        var intent = data(create(owner, key(), owner.usd(), "4.00"));
        String id = intent.path("intentId").asText(), handoff = handoff(intent);
        String forged = "A".repeat(43);

        assertThat(error(approve(owner, id, forged, PIN))).isEqualTo("OWNER_TRANSFER_INVALID");
        assertThat(call("POST", "/merchant-transfers/" + id + "/approve", owner.customer(), Map.of("pin", PIN)).statusCode()).isEqualTo(400);
        assertThat(call("POST", "/merchant-transfers/" + id + "/approve", owner.customer(),
                Map.of("handoffToken", "short", "pin", PIN)).statusCode()).isEqualTo(400);
        assertThat(call("GET", "/merchant-transfers/" + id, owner.customer(), null).statusCode()).isEqualTo(400);
        // Another customer cannot see or approve it, even holding the token.
        assertThat(approve(stranger, id, handoff, PIN).statusCode()).isEqualTo(404);
        assertThat(call("GET", "/merchant-transfers/" + id, stranger.customer(), null, Map.of("X-Merchant-Handoff", handoff)).statusCode()).isEqualTo(404);
        assertThat(call("POST", "/merchant-transfers/" + id + "/deny", stranger.customer(), Map.of("handoffToken", handoff)).statusCode()).isEqualTo(404);
        // Session types never cross.
        assertThat(error(call("POST", "/merchant-transfers/" + id + "/approve", owner.merchant(),
                Map.of("handoffToken", handoff, "pin", PIN)))).isEqualTo("CUSTOMER_SESSION_REQUIRED");
        assertThat(error(call("GET", "/merchant-transfers/" + id, owner.merchant(), null, Map.of("X-Merchant-Handoff", handoff))))
                .isEqualTo("CUSTOMER_SESSION_REQUIRED");
        assertThat(error(call("GET", "/merchants/me/owner-transfers/" + id, owner.customer(), null))).isEqualTo("MERCHANT_SESSION_REQUIRED");
        assertThat(error(call("POST", "/merchants/me/owner-transfers/" + id + "/cancel", owner.customer(), null))).isEqualTo("MERCHANT_SESSION_REQUIRED");
        assertThat(error(call("POST", "/merchants/me/owner-transfers", owner.customer(),
                Map.of("sourceAccountNumber", owner.usd(), "amount", "1.00"), Map.of("Idempotency-Key", key())))).isEqualTo("MERCHANT_SESSION_REQUIRED");
        // Other shops see nothing.
        assertThat(call("GET", "/merchants/me/owner-transfers/" + id, stranger.merchant(), null).statusCode()).isEqualTo(404);
        assertThat(call("POST", "/merchants/me/owner-transfers/" + id + "/cancel", stranger.merchant(), null).statusCode()).isEqualTo(404);
        assertThat(balance(owner.usd())).isEqualByComparingTo("20.00");
        assertThat(statusOf(id)).isEqualTo("PENDING");
        assertThat(transfersOf(owner) + transfersOf(stranger)).isZero();
    }

    @Test void cancelledDeniedAndExpiredIntentsNeverPost() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "20.00");

        var cancelled = data(create(owner, key(), owner.usd(), "4.00"));
        var cancelResult = data(call("POST", "/merchants/me/owner-transfers/" + cancelled.path("intentId").asText() + "/cancel", owner.merchant(), null));
        assertThat(cancelResult.path("status").asText()).isEqualTo("CANCELLED");
        var afterCancel = approve(owner, cancelled.path("intentId").asText(), handoff(cancelled), PIN);
        assertThat(afterCancel.statusCode()).isEqualTo(409);
        assertThat(error(afterCancel)).isEqualTo("OWNER_TRANSFER_CANCELLED");

        var denied = data(create(owner, key(), owner.usd(), "4.00"));
        var denial = data(call("POST", "/merchant-transfers/" + denied.path("intentId").asText() + "/deny", owner.customer(),
                Map.of("handoffToken", handoff(denied))));
        assertThat(denial.path("status").asText()).isEqualTo("DENIED");
        assertThat(denial.path("callbackUri").asText()).contains("error=access_denied");
        assertThat(error(approve(owner, denied.path("intentId").asText(), handoff(denied), PIN))).isEqualTo("OWNER_TRANSFER_DENIED");
        assertThat(data(call("GET", "/merchants/me/owner-transfers/" + denied.path("intentId").asText(), owner.merchant(), null))
                .path("status").asText()).isEqualTo("DENIED");

        var expiring = data(create(owner, key(), owner.usd(), "4.00"));
        UUID expiringId = UUID.fromString(expiring.path("intentId").asText());
        jdbc.update("UPDATE merchant_owner_transfers SET created_at=created_at-INTERVAL '1 hour',expires_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=?", expiringId);
        assertThat(error(call("GET", "/merchant-transfers/" + expiringId, owner.customer(), null, Map.of("X-Merchant-Handoff", handoff(expiring)))))
                .isEqualTo("OWNER_TRANSFER_EXPIRED");
        assertThat(error(approve(owner, expiringId.toString(), handoff(expiring), PIN))).isEqualTo("OWNER_TRANSFER_EXPIRED");
        assertThat(data(call("GET", "/merchants/me/owner-transfers/" + expiringId, owner.merchant(), null)).path("status").asText()).isEqualTo("EXPIRED");
        // A lapsed intent does not block a new one.
        assertThat(create(owner, key(), owner.usd(), "1.00").statusCode()).isEqualTo(201);

        assertThat(balance(owner.usd())).isEqualByComparingTo("20.00");
        assertThat(transfersOf(owner)).isZero();
    }

    @Test void approvingAndCancellingTheSameIntentHaveExactlyOneOutcome() throws Exception {
        for (int round = 0; round < 3; round++) {
            var owner = owner(true);
            setBalance(owner.usd(), "20.00");
            var intent = data(create(owner, key(), owner.usd(), "5.00"));
            String id = intent.path("intentId").asText(), handoff = handoff(intent);
            var results = race(() -> approve(owner, id, handoff, PIN),
                    () -> call("POST", "/merchants/me/owner-transfers/" + id + "/cancel", owner.merchant(), null));
            assertThat(results.get(1).statusCode()).as(results.get(1).body()).isEqualTo(200);
            String finalStatus = data(results.get(1)).path("status").asText();
            if (results.get(0).statusCode() == 200) {
                assertThat(finalStatus).isEqualTo("COMPLETED");
                assertThat(balance(owner.usd())).isEqualByComparingTo("15.00");
                assertThat(balance(owner.personalUsd())).isEqualByComparingTo("205.00");
                assertThat(transfersOf(owner)).isEqualTo(1);
            } else {
                assertThat(finalStatus).isEqualTo("CANCELLED");
                assertThat(error(results.get(0))).isEqualTo("OWNER_TRANSFER_CANCELLED");
                assertThat(balance(owner.usd())).isEqualByComparingTo("20.00");
                assertThat(transfersOf(owner)).isZero();
            }
        }
    }

    @Test void approvingTwicePostsOnce() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "20.00");
        var intent = data(create(owner, key(), owner.usd(), "5.00"));
        String id = intent.path("intentId").asText(), handoff = handoff(intent);
        var first = data(approve(owner, id, handoff, PIN));
        var replay = approve(owner, id, handoff, PIN);
        assertThat(replay.statusCode()).as(replay.body()).isEqualTo(200);
        assertThat(data(replay).path("callbackUri").asText()).isEqualTo(first.path("callbackUri").asText());
        assertThat(balance(owner.usd())).isEqualByComparingTo("15.00");

        var next = data(create(owner, key(), owner.usd(), "5.00"));
        var results = race(() -> approve(owner, next.path("intentId").asText(), handoff(next), PIN),
                () -> approve(owner, next.path("intentId").asText(), handoff(next), PIN));
        assertThat(results.get(0).statusCode()).as(results.get(0).body()).isEqualTo(200);
        assertThat(results.get(1).statusCode()).as(results.get(1).body()).isEqualTo(200);
        assertThat(transfersOf(owner)).isEqualTo(2);
        assertThat(balance(owner.usd())).isEqualByComparingTo("10.00");
        assertThat(balance(owner.personalUsd())).isEqualByComparingTo("210.00");
    }

    @Test void insufficientFundsAtApprovalFailsTheIntentWithoutMovingMoney() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "10.00");
        var intent = data(create(owner, key(), owner.usd(), "10.00"));
        String id = intent.path("intentId").asText(), handoff = handoff(intent);
        setBalance(owner.usd(), "5.00");
        var approved = approve(owner, id, handoff, PIN);
        assertThat(approved.statusCode()).as(approved.body()).isEqualTo(200);
        assertThat(data(approved).path("status").asText()).isEqualTo("FAILED");
        assertThat(data(approved).path("failureCode").asText()).isEqualTo("INSUFFICIENT_FUNDS");
        assertThat(balance(owner.usd())).isEqualByComparingTo("5.00");
        assertThat(balance(owner.personalUsd())).isEqualByComparingTo("200.00");
        assertThat(statusOf(id)).isEqualTo("FAILED");
        assertThat(data(call("GET", "/merchants/me/owner-transfers/" + id, owner.merchant(), null)).path("failureCode").asText())
                .isEqualTo("INSUFFICIENT_FUNDS");
        assertThat(error(approve(owner, id, handoff, PIN))).isEqualTo("OWNER_TRANSFER_FAILED");
        assertThat(transfersOf(owner)).isZero();
        // The owner can start over.
        assertThat(create(owner, key(), owner.usd(), "5.00").statusCode()).isEqualTo(201);
    }

    @Test void aSuspendedShopCannotTransferOrApprove() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "20.00");
        var intent = data(create(owner, key(), owner.usd(), "4.00"));
        String id = intent.path("intentId").asText(), handoff = handoff(intent);
        jdbc.update("UPDATE merchants SET status='SUSPENDED' WHERE owner_user_id=?", owner.id());
        var blocked = approve(owner, id, handoff, PIN);
        assertThat(blocked.statusCode()).isEqualTo(409);
        assertThat(error(blocked)).isEqualTo("MERCHANT_INACTIVE");
        assertThat(error(create(owner, key(), owner.usd(), "1.00"))).isEqualTo("MERCHANT_INACTIVE");
        assertThat(balance(owner.usd())).isEqualByComparingTo("20.00");
        assertThat(statusOf(id)).isEqualTo("PENDING");
        jdbc.update("UPDATE merchants SET status='ACTIVE' WHERE owner_user_id=?", owner.id());
        assertThat(data(approve(owner, id, handoff, PIN)).path("status").asText()).isEqualTo("COMPLETED");
    }

    @Test void aTamperedIntentIsRefusedAndOtherBusinessDebitsStayBlocked() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "20.00");
        var intent = data(create(owner, key(), owner.usd(), "4.00"));
        // Changing the amount in the table without the matching intent hash must stop the posting.
        jdbc.update("UPDATE merchant_owner_transfers SET amount=15.00 WHERE id=?", UUID.fromString(intent.path("intentId").asText()));
        var tampered = approve(owner, intent.path("intentId").asText(), handoff(intent), PIN);
        assertThat(tampered.statusCode()).isEqualTo(409);
        assertThat(error(tampered)).isEqualTo("OWNER_TRANSFER_INVALID");
        assertThat(balance(owner.usd())).isEqualByComparingTo("20.00");

        // The general guard still blocks every other debit of a business wallet.
        var debit = call("POST", "/transactions/transfer", owner.customer(), Map.of("sourceAccountNumber", owner.usd(),
                "destinationAccountNumber", owner.personalUsd(), "amount", "1.00", "currency", "USD"), Map.of("Idempotency-Key", key()));
        assertThat(error(debit)).isEqualTo("MERCHANT_WALLET_RESTRICTED");
        assertThat(balance(owner.usd())).isEqualByComparingTo("20.00");
    }

    @Test void creationIsIdempotentAndOneIntentIsOpenAtATime() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "20.00");
        String key = key();
        var first = create(owner, key, owner.usd(), "4.00");
        assertThat(first.statusCode()).isEqualTo(201);
        var replay = create(owner, key, owner.usd(), "4");
        assertThat(replay.statusCode()).as(replay.body()).isEqualTo(200);
        assertThat(data(replay).path("intentId").asText()).isEqualTo(data(first).path("intentId").asText());
        assertThat(data(replay).path("state").asText()).isEqualTo(data(first).path("state").asText());
        assertThat(handoff(data(replay))).isNotEqualTo(handoff(data(first)));
        String id = data(first).path("intentId").asText();
        // The replay replaced the old handoff secret.
        assertThat(error(approve(owner, id, handoff(data(first)), PIN))).isEqualTo("OWNER_TRANSFER_INVALID");
        assertThat(error(create(owner, key, owner.usd(), "5.00"))).isEqualTo("IDEMPOTENCY_CONFLICT");
        assertThat(error(create(owner, key(), owner.usd(), "1.00"))).isEqualTo("OWNER_TRANSFER_IN_PROGRESS");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM merchant_owner_transfers WHERE owner_user_id=?", Long.class, owner.id())).isEqualTo(1);
        assertThat(data(approve(owner, id, handoff(data(replay)), PIN)).path("status").asText()).isEqualTo("COMPLETED");
        // After completion the same key replays the finished intent, without a way to approve it again.
        var done = create(owner, key, owner.usd(), "4.00");
        assertThat(data(done).path("status").asText()).isEqualTo("COMPLETED");
        assertThat(data(done).path("approvalUri").isNull()).isTrue();
        assertThat(transfersOf(owner)).isEqualTo(1);
    }

    @Test void auditNeverRecordsPinsTokensOrFullAccountNumbers() throws Exception {
        var owner = owner(true);
        setBalance(owner.usd(), "20.00");
        var intent = data(create(owner, key(), owner.usd(), "4.00"));
        String id = intent.path("intentId").asText(), handoff = handoff(intent);
        approve(owner, id, handoff, "1111");
        approve(owner, id, handoff, PIN);
        var rows = jdbc.queryForList("""
                SELECT module_name||' '||action||' '||coalesce(target_resource_id,'')||' '||coalesce(details,'') FROM audit_logs
                WHERE action LIKE 'OWNER_TRANSFER%' OR target_resource_id=?
                """, String.class, id);
        assertThat(rows).isNotEmpty();
        String text = String.join("\n", rows);
        assertThat(text).contains("OWNER_TRANSFER_CREATED").contains("OWNER_TRANSFER_COMPLETED");
        assertThat(text).doesNotContain(handoff).doesNotContain(PIN).doesNotContain(owner.usd()).doesNotContain(owner.personalUsd());
    }

    // ---- fixtures ----

    Owner owner(boolean withWallets) throws Exception {
        record Created(long id, String merchant, String customer, String usd, String khr) {}
        var created = new TransactionTemplate(txManager).execute(s -> {
            var u = users.saveAndFlush(User.builder().username("m8.owner." + UUID.randomUUID()).firstName("Synthetic").lastName("Owner")
                    .profileComplete(true).enabled(true).roles(new HashSet<>(Set.of(roles.findByName(ERole.ROLE_CUSTOMER).orElseThrow()))).build());
            String usd = null, khr = null;
            if (withWallets) {
                var wallets = accounts.createDefaultUserWallets(u);
                usd = wallets.get(0).getAccountNumber(); khr = wallets.get(1).getAccountNumber();
            }
            TokenResponseDto customer = sessions.create(u, devices.bind(u, UUID.randomUUID().toString(), "Customer fixture", "MOBILE", "Android", "127.0.0.1"));
            TokenResponseDto merchant = sessions.createMerchant(u, devices.bind(u, "merchant:" + UUID.randomUUID(), "Merchant fixture", "MOBILE", "Android", "127.0.0.1"));
            return new Created(u.getId(), merchant.getAccessToken(), customer.getAccessToken(), usd, khr);
        });
        var prepared = call("POST", "/auth/pin/prepare", created.customer(), null);
        assertThat(prepared.statusCode()).as(prepared.body()).isEqualTo(200);
        var setup = call("POST", "/auth/pin/setup", null, Map.of("ticket", data(prepared).path("ticket").asText(), "pin", PIN, "confirmPin", PIN));
        assertThat(setup.statusCode()).as(setup.body()).isEqualTo(200);
        String customerToken = data(setup).path("accessToken").asText();
        var registered = call("POST", "/merchants/me/registration", created.merchant(), Map.of("storeName", "Sokha Coffee",
                "categoryCode", "FOOD_DRINK", "phone", "012 345 678", "city", "Phnom Penh", "address", "St. 51"),
                Map.of("Idempotency-Key", key()));
        assertThat(registered.statusCode()).as(registered.body()).isEqualTo(201);
        var profile = data(registered);
        return new Owner(created.id(), created.merchant(), customerToken, profile.path("shop").path("merchantId").asText(),
                profile.path("wallets").get(0).path("accountNumber").asText(), profile.path("wallets").get(1).path("accountNumber").asText(),
                created.usd(), created.khr());
    }

    HttpResponse<String> create(Owner owner, String key, String source, String amount) throws Exception {
        return create(owner, key, Map.of("sourceAccountNumber", source, "amount", amount));
    }
    HttpResponse<String> create(Owner owner, String key, Map<String, Object> body) throws Exception {
        return call("POST", "/merchants/me/owner-transfers", owner.merchant(), body, Map.of("Idempotency-Key", key));
    }
    HttpResponse<String> approve(Owner owner, String id, String handoff, String pin) throws Exception {
        return call("POST", "/merchant-transfers/" + id + "/approve", owner.customer(), Map.of("handoffToken", handoff, "pin", pin));
    }
    String handoff(JsonNode intent) {
        String uri = intent.path("approvalUri").asText();
        return uri.substring(uri.indexOf("handoffToken=") + "handoffToken=".length());
    }
    void setBalance(String number, String value) { jdbc.update("UPDATE accounts SET balance=? WHERE account_number=?", new BigDecimal(value), number); }
    BigDecimal balance(String number) { return jdbc.queryForObject("SELECT balance FROM accounts WHERE account_number=?", BigDecimal.class, number); }
    String statusOf(String id) { return jdbc.queryForObject("SELECT status FROM merchant_owner_transfers WHERE id=?", String.class, UUID.fromString(id)); }
    int failures(Owner owner) { return jdbc.queryForObject("SELECT failed_attempts FROM customer_app_pins WHERE user_id=?", Integer.class, owner.id()); }
    long transfersOf(Owner owner) {
        return jdbc.queryForObject("SELECT count(*) FROM transactions WHERE operation='OWNER_TRANSFER' AND initiated_by_user_id=?", Long.class, owner.id());
    }
    long collections(Owner owner) {
        return jdbc.queryForObject("SELECT count(*) FROM merchant_collections c JOIN merchants m ON m.id=c.merchant_id WHERE m.owner_user_id=?", Long.class, owner.id());
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
