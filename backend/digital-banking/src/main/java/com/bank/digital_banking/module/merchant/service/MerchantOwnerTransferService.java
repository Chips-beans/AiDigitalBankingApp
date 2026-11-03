package com.bank.digital_banking.module.merchant.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.common.util.CurrencyUtils;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.common.util.TransactionLockPolicy;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthConfig;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthCrypto;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthService;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.auth.service.AppPinService;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthDtos;
import com.bank.digital_banking.module.transaction.service.FinancialPostingService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

import static com.bank.digital_banking.module.merchant.dto.MerchantOwnerTransferDtos.*;

/**
 * Owner transfers (M8). A Merchant session creates an intent; the owner approves it with a fresh
 * PIN in the Customer App, and approval posts the transfer in the same database transaction, so
 * there is no approved-but-unposted state. Every path locks the owner row first, then the intent
 * row, then (inside the posting) both accounts in id order.
 */
@Service @RequiredArgsConstructor
public class MerchantOwnerTransferService {
    private final JdbcTemplate jdbc;
    private final UserRepository users;
    private final MerchantAuthService sessions;
    private final MerchantShopService shops;
    private final FinancialPostingService posting;
    private final AppPinService pins;
    private final AuditTrail audit;
    private final TransactionLockPolicy locks;
    private final MerchantAuthConfig config;
    @Value("${app.merchant.owner-transfer-ttl-seconds:300}") private int ttlSeconds;

    private record Row(UUID id, long merchantId, long ownerId, String source, String destination, String currency,
                       BigDecimal amount, String status, String failure, String requestHash, String intentHash,
                       String handoffHash, String state, OffsetDateTime createdAt, OffsetDateTime expiresAt,
                       Long transactionId) {
        boolean lapsed() { return !expiresAt.isAfter(OffsetDateTime.now()); }
    }

    // ---- Merchant session ----

    @Transactional
    public CreatedTransfer create(User user, UUID sid, String key, NewOwnerTransfer request) {
        config.requireTransfers();
        if (key == null || !key.matches("[A-Za-z0-9_-]{16,128}"))
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required");
        sessions.merchant(user, sid);
        User owner = owner(user.getId());
        String keyHash = HashUtils.sha256(key);
        String requestHash = HashUtils.sha256(String.join("\u001F", request.getSourceAccountNumber(),
                request.getAmount().stripTrailingZeros().toPlainString()));
        var prior = rows("WHERE t.owner_user_id=? AND t.key_hash=?", owner.getId(), keyHash);
        if (!prior.isEmpty()) {
            if (!prior.getFirst().requestHash().equals(requestHash)) throw new ApiException(HttpStatus.CONFLICT,
                    "IDEMPOTENCY_CONFLICT", "This transfer key was already used with different details");
            return new CreatedTransfer(false, replay(settle(prior.getFirst())));
        }
        var shop = shops.requireShop(owner);
        if (!shop.active()) throw new ApiException(HttpStatus.FORBIDDEN, "MERCHANT_INACTIVE", "This shop cannot transfer money right now");
        var source = jdbc.query("""
                SELECT currency,status,balance FROM accounts
                WHERE account_number=? AND merchant_id=? AND account_category='MERCHANT' AND user_id=?
                """, (r, i) -> new String[]{r.getString(1), r.getString(2), r.getBigDecimal(3).toPlainString()},
                request.getSourceAccountNumber(), shop.id(), owner.getId()).stream().findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("Not available"));
        String currency = source[0];
        BigDecimal amount = CurrencyUtils.amount(request.getAmount(), currency, false);
        if (!"ACTIVE".equals(source[1])) throw new ApiException(HttpStatus.CONFLICT, "ACCOUNT_INACTIVE", "Account is not active");
        if (new BigDecimal(source[2]).compareTo(amount) < 0)
            throw new ApiException(HttpStatus.CONFLICT, "INSUFFICIENT_FUNDS", "Your business wallet balance is not enough");
        // The server picks the destination: the owner's earliest active personal wallet in this currency.
        String destination = jdbc.queryForList("""
                SELECT account_number FROM accounts WHERE user_id=? AND account_category='WALLET' AND currency=?
                    AND status='ACTIVE' ORDER BY id LIMIT 1
                """, String.class, owner.getId(), currency).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.CONFLICT, "OWNER_WALLET_REQUIRED",
                        "Open a " + currency + " wallet in Kesor Bank first"));

        jdbc.update("""
                UPDATE merchant_owner_transfers SET status='EXPIRED',completed_at=CURRENT_TIMESTAMP
                WHERE owner_user_id=? AND status='PENDING' AND expires_at<=CURRENT_TIMESTAMP
                """, owner.getId());
        if (jdbc.queryForObject("SELECT count(*) FROM merchant_owner_transfers WHERE owner_user_id=? AND status='PENDING'",
                Long.class, owner.getId()) > 0)
            throw new ApiException(HttpStatus.CONFLICT, "OWNER_TRANSFER_IN_PROGRESS", "Finish or cancel your open transfer first");

        UUID id = UUID.randomUUID();
        String handoff = MerchantAuthCrypto.random(), state = MerchantAuthCrypto.random();
        jdbc.update("""
                INSERT INTO merchant_owner_transfers(id,merchant_id,owner_user_id,source_account_number,
                    destination_account_number,currency,amount,key_hash,request_hash,intent_hash,handoff_hash,state,expires_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP + make_interval(secs => ?))
                """, id, shop.id(), owner.getId(), request.getSourceAccountNumber(), destination, currency, amount, keyHash,
                requestHash, intentHash(id, request.getSourceAccountNumber(), destination, currency, amount),
                HashUtils.sha256(handoff), state, Math.max(60, Math.min(ttlSeconds, 900)));
        audit.successAs(owner, "MERCHANT", "OWNER_TRANSFER_CREATED", id.toString());
        return new CreatedTransfer(true, view(rows("WHERE t.id=?", id).getFirst(), handoff));
    }

    @Transactional
    public TransferView status(User user, UUID sid, UUID id) {
        sessions.merchant(user, sid);
        var shop = shops.requireShop(owner(user.getId()));
        var row = rows("WHERE t.id=? AND t.merchant_id=?", id, shop.id()).stream().findFirst().orElseThrow(this::notFound);
        return view(settle(row), null);
    }

    @Transactional
    public TransferView cancel(User user, UUID sid, UUID id) {
        sessions.merchant(user, sid);
        var shop = shops.requireShop(owner(user.getId()));
        rows("WHERE t.id=? AND t.merchant_id=?", id, shop.id()).stream().findFirst().orElseThrow(this::notFound);
        var row = rows("WHERE t.id=? FOR UPDATE OF t", id).getFirst();
        if ("PENDING".equals(row.status())) {
            // A lapsed intent is reported as expired; an approved one stays completed.
            boolean expired = row.lapsed();
            jdbc.update("UPDATE merchant_owner_transfers SET status=?,completed_at=CURRENT_TIMESTAMP WHERE id=?",
                    expired ? "EXPIRED" : "CANCELLED", id);
            if (!expired) audit.successAs(owner(user.getId()), "MERCHANT", "OWNER_TRANSFER_CANCELLED", id.toString());
            row = rows("WHERE t.id=?", id).getFirst();
        }
        return view(row, null);
    }

    // ---- Customer session ----

    @Transactional
    public TransferDetails details(User user, UUID sid, UUID id, String handoff) {
        config.requireTransfers(); locks.apply();
        user = owner(user.getId());
        var row = ownedRow(id, user.getId(), false);
        requireHandoff(row, handoff);
        sessions.customer(user, sid);
        requirePending(row);
        return new TransferDetails(id, shopName(row.merchantId()), MerchantSettlement.mask(row.source()),
                MerchantSettlement.mask(row.destination()), row.currency(), MerchantShopService.money(row.amount(), row.currency()),
                row.status(), row.expiresAt(), OffsetDateTime.now(), MerchantAuthConfig.PACKAGE);
    }

    /** Verifies the PIN and posts the transfer in this one transaction. Failed PIN attempts still commit. */
    @Transactional(noRollbackFor = AppPinService.PinRejected.class)
    public TransferOutcome approve(User user, UUID sid, UUID id, MerchantAuthDtos.Approve request) {
        config.requireTransfers(); locks.apply();
        user = owner(user.getId());
        var row = ownedRow(id, user.getId(), true);
        requireHandoff(row, request.handoffToken());
        sessions.customer(user, sid);
        if ("COMPLETED".equals(row.status())) return outcome(row, "COMPLETED", null, null);
        requirePending(row);
        if (!MessageDigest.isEqual(row.intentHash().getBytes(StandardCharsets.US_ASCII),
                intentHash(row.id(), row.source(), row.destination(), row.currency(), row.amount()).getBytes(StandardCharsets.US_ASCII)))
            throw new ApiException(HttpStatus.CONFLICT, "OWNER_TRANSFER_INVALID", "This transfer request is no longer valid");
        String shopStatus = jdbc.queryForList("SELECT status::text FROM merchants WHERE id=? AND owner_user_id=?", String.class,
                row.merchantId(), user.getId()).stream().findFirst().orElse(null);
        if (!"ACTIVE".equals(shopStatus)) throw new ApiException(HttpStatus.CONFLICT, "MERCHANT_INACTIVE",
                "This shop cannot transfer money right now");

        pins.verifyForOwnerTransfer(user, sid, request.pin());
        var posted = posting.postOwnerTransfer(user, row.merchantId(), row.source(), row.destination(), row.amount(), row.currency());
        if (posted.isEmpty()) {
            jdbc.update("""
                    UPDATE merchant_owner_transfers SET status='FAILED',failure_code='INSUFFICIENT_FUNDS',
                        completed_at=CURRENT_TIMESTAMP WHERE id=? AND status='PENDING'
                    """, id);
            audit.successAs(user, "MERCHANT", "OWNER_TRANSFER_FAILED", id.toString());
            return outcome(row, "FAILED", "INSUFFICIENT_FUNDS", "failed");
        }
        int updated = jdbc.update("""
                UPDATE merchant_owner_transfers SET status='COMPLETED',transaction_id=?,completed_at=CURRENT_TIMESTAMP
                WHERE id=? AND status='PENDING'
                """, posted.get().getId(), id);
        if (updated != 1) throw new IllegalStateException("Owner transfer changed during approval");
        audit.successAs(user, "MERCHANT", "OWNER_TRANSFER_COMPLETED", id.toString());
        return outcome(row, "COMPLETED", null, null);
    }

    @Transactional
    public TransferOutcome deny(User user, UUID sid, UUID id, MerchantAuthDtos.Handoff request) {
        config.requireTransfers(); locks.apply();
        user = owner(user.getId());
        var row = ownedRow(id, user.getId(), true);
        requireHandoff(row, request.handoffToken());
        sessions.customer(user, sid);
        requirePending(row);
        jdbc.update("UPDATE merchant_owner_transfers SET status='DENIED',completed_at=CURRENT_TIMESTAMP WHERE id=? AND status='PENDING'", id);
        audit.successAs(user, "MERCHANT", "OWNER_TRANSFER_DENIED", id.toString());
        return outcome(row, "DENIED", null, "access_denied");
    }

    // ---- helpers ----

    private TransferOutcome outcome(Row row, String status, String failure, String error) {
        String uri = config.transferCallback + "?intentId=" + row.id() + "&state=" + row.state()
                + (error == null ? "" : "&error=" + error);
        return new TransferOutcome(row.id(), status, failure, uri, MerchantAuthConfig.PACKAGE);
    }

    /** Only the owner's own intent; anything else is indistinguishable from a missing one. */
    private Row ownedRow(UUID id, long ownerId, boolean lock) {
        var row = rows("WHERE t.id=?" + (lock ? " FOR UPDATE OF t" : ""), id).stream().findFirst().orElseThrow(this::notFound);
        if (row.ownerId() != ownerId) throw notFound();
        return row;
    }

    private void requireHandoff(Row row, String raw) {
        if (!MerchantAuthCrypto.matches(row.handoffHash(), raw))
            throw new ApiException(HttpStatus.BAD_REQUEST, "OWNER_TRANSFER_INVALID", "This transfer request is invalid");
    }

    private void requirePending(Row row) {
        String code = switch (row.status()) {
            case "PENDING" -> row.lapsed() ? "OWNER_TRANSFER_EXPIRED" : null;
            case "DENIED" -> "OWNER_TRANSFER_DENIED";
            case "CANCELLED" -> "OWNER_TRANSFER_CANCELLED";
            case "EXPIRED" -> "OWNER_TRANSFER_EXPIRED";
            case "FAILED" -> "OWNER_TRANSFER_FAILED";
            default -> "OWNER_TRANSFER_COMPLETED";
        };
        if (code != null) throw new ApiException(HttpStatus.CONFLICT, code, "This transfer request is no longer available");
    }

    /** Persists a lazy expiry; terminal rows are returned as they are. */
    private Row settle(Row row) {
        if (!"PENDING".equals(row.status()) || !row.lapsed()) return row;
        jdbc.update("""
                UPDATE merchant_owner_transfers SET status='EXPIRED',completed_at=CURRENT_TIMESTAMP
                WHERE id=? AND status='PENDING' AND expires_at<=CURRENT_TIMESTAMP
                """, row.id());
        return rows("WHERE t.id=?", row.id()).getFirst();
    }

    /** The handoff secret is stored hashed, so a replayed create of a waiting intent gets a fresh one. */
    private TransferView replay(Row row) {
        if (!"PENDING".equals(row.status())) return view(row, null);
        String handoff = MerchantAuthCrypto.random();
        jdbc.update("UPDATE merchant_owner_transfers SET handoff_hash=? WHERE id=? AND status='PENDING'",
                HashUtils.sha256(handoff), row.id());
        return view(row, handoff);
    }

    private TransferView view(Row row, String handoff) {
        TransferReceipt receipt = row.transactionId() == null ? null : jdbc.query("""
                SELECT x.reference_number,o.completed_at FROM merchant_owner_transfers o
                JOIN transactions x ON x.id=o.transaction_id WHERE o.id=?
                """, (r, i) -> new TransferReceipt(r.getString(1), r.getObject(2, OffsetDateTime.class)), row.id())
                .stream().findFirst().orElse(null);
        boolean open = handoff != null && "PENDING".equals(row.status());
        return new TransferView(row.id(), row.status(), row.source(), MerchantSettlement.mask(row.destination()),
                row.currency(), MerchantShopService.money(row.amount(), row.currency()), row.createdAt(), row.expiresAt(),
                OffsetDateTime.now(), row.failure(), receipt,
                open ? config.transferApproval + "?intentId=" + row.id() + "&handoffToken=" + handoff : null,
                open ? row.state() : null);
    }

    private String shopName(long merchantId) {
        return jdbc.queryForObject("SELECT store_name FROM merchants WHERE id=?", String.class, merchantId);
    }

    private List<Row> rows(String where, Object... args) {
        return jdbc.query("""
                SELECT t.id,t.merchant_id,t.owner_user_id,t.source_account_number,t.destination_account_number,t.currency,
                    t.amount,t.status,t.failure_code,t.request_hash,t.intent_hash,t.handoff_hash,t.state,t.created_at,
                    t.expires_at,t.transaction_id FROM merchant_owner_transfers t
                """ + where, (r, i) -> new Row(r.getObject(1, UUID.class), r.getLong(2), r.getLong(3), r.getString(4),
                r.getString(5), r.getString(6), r.getBigDecimal(7), r.getString(8), r.getString(9), r.getString(10),
                r.getString(11), r.getString(12), r.getString(13), r.getObject(14, OffsetDateTime.class),
                r.getObject(15, OffsetDateTime.class), r.getObject(16, Long.class)), args);
    }

    /** Binds the exact source, destination, currency and amount; recomputed from the row at approval. */
    static String intentHash(UUID id, String source, String destination, String currency, BigDecimal amount) {
        return HashUtils.sha256(String.join("|", id.toString(), source, destination, currency,
                amount.setScale(2, java.math.RoundingMode.UNNECESSARY).toPlainString()));
    }

    private User owner(long id) {
        return users.findLockedById(id).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                "SESSION_INVALID", "Session is expired or revoked"));
    }

    private ResourceNotFoundException notFound() { return new ResourceNotFoundException("Not available"); }
}
