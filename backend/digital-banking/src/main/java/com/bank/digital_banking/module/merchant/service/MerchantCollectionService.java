package com.bank.digital_banking.module.merchant.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.common.util.CurrencyUtils;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthService;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.payment.entity.Payment;
import com.bank.digital_banking.module.payment.entity.PaymentStatus;
import com.bank.digital_banking.module.payment.qr.QrCodeEngine;
import com.bank.digital_banking.module.payment.repository.PaymentRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.security.SecureRandom;
import java.time.*;
import java.util.*;

import static com.bank.digital_banking.module.merchant.dto.MerchantCollectionDtos.*;
import static com.bank.digital_banking.module.merchant.dto.MerchantShopDtos.Wallet;

/**
 * Merchant dashboard, wallet activity and QR collection (M5/M6). Every call starts with
 * the Merchant session check, which locks the owner row, and derives the shop from it.
 * Request state changes lock the registered payment row first, the same order the
 * Customer QR payment uses, so a paid request can never be cancelled or hidden.
 */
@Service @RequiredArgsConstructor
public class MerchantCollectionService {
    public static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Phnom_Penh");
    private static final String CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final SecureRandom RANDOM = new SecureRandom();

    private final JdbcTemplate jdbc;
    private final UserRepository users;
    private final MerchantAuthService sessions;
    private final MerchantShopService shops;
    private final PaymentRepository payments;
    private final QrCodeEngine engine;
    private final AuditTrail audit;
    @Value("${app.merchant.payment-request-ttl-seconds:300}") private int ttlSeconds;

    private record RequestRow(UUID id, long paymentId, String reference, String status, String currency,
                              BigDecimal amount, String orderReference, OffsetDateTime createdAt,
                              OffsetDateTime expiresAt, String requestHash) {}

    @Transactional
    public Dashboard dashboard(User user, UUID sid) {
        sessions.merchant(user, sid);
        User owner = owner(user);
        var profile = shops.profileOf(owner);
        if (profile.shop() == null) return new Dashboard(profile, today().toString(), List.of(), List.of(), now());
        var shop = shops.requireShop(owner);
        OffsetDateTime start = today().atStartOfDay(BUSINESS_ZONE).toOffsetDateTime();
        Map<String, Totals> totals = new LinkedHashMap<>();
        for (String currency : List.of("KHR", "USD")) totals.put(currency, new Totals(currency, 0, MerchantShopService.money(BigDecimal.ZERO, currency)));
        jdbc.query("""
                SELECT currency,count(*),coalesce(sum(amount),0) FROM merchant_collections
                WHERE merchant_id=? AND created_at>=? GROUP BY currency
                """, rs -> {
            String currency = rs.getString(1);
            totals.put(currency, new Totals(currency, rs.getLong(2), MerchantShopService.money(rs.getBigDecimal(3), currency)));
        }, shop.id(), start);
        var recent = jdbc.query(COLLECTION_SQL + " WHERE c.merchant_id=? ORDER BY c.created_at DESC, c.transaction_id DESC LIMIT 10",
                (r, i) -> collection(r), shop.id());
        return new Dashboard(profile, today().toString(), List.copyOf(totals.values()), recent, now());
    }

    @Transactional
    public WalletDetail wallet(User user, UUID sid, String number, int page) {
        sessions.merchant(user, sid);
        var shop = shops.requireShop(owner(user));
        if (number == null || !number.matches("[0-9]{10,20}")) throw notFound();
        int size = 20, safePage = Math.max(0, Math.min(page, 50));
        var wallet = jdbc.query("""
                SELECT id,account_number,currency,status,balance FROM accounts
                WHERE account_number=? AND merchant_id=? AND account_category='MERCHANT'
                """, (r, i) -> Map.entry(r.getLong(1), new Wallet(r.getString(2), "MERCHANT", shop.code(), r.getString(3),
                r.getString(4), MerchantShopService.money(r.getBigDecimal(5), r.getString(3)))), number, shop.id())
                .stream().findFirst().orElseThrow(MerchantCollectionService::notFound);
        long accountId = wallet.getKey();
        String currency = wallet.getValue().currency();
        var rows = jdbc.query("""
                SELECT t.reference_number,t.source_account_id=? AS outgoing,t.amount,t.credit_amount,t.transaction_type,
                    c.payer_name,c.payer_account_masked,t.created_at
                FROM transactions t LEFT JOIN merchant_collections c ON c.transaction_id=t.id
                WHERE (t.source_account_id=? OR t.destination_account_id=?) AND t.status='SUCCESS'
                ORDER BY t.id DESC LIMIT ? OFFSET ?
                """, (r, i) -> {
            boolean outgoing = r.getBoolean(2);
            BigDecimal amount = outgoing || r.getBigDecimal(4) == null ? r.getBigDecimal(3) : r.getBigDecimal(4);
            String kind = outgoing ? "TRANSFER_OUT" : r.getString(6) != null ? "QR_PAYMENT"
                    : "DEPOSIT".equals(r.getString(5)) ? "DEPOSIT" : "TRANSFER_IN";
            return new Activity(r.getString(1), kind, outgoing ? "OUT" : "IN", MerchantShopService.money(amount, currency),
                    currency, r.getString(6), r.getString(7), r.getObject(8, OffsetDateTime.class));
        }, accountId, accountId, accountId, size + 1, safePage * size);
        boolean more = rows.size() > size;
        return new WalletDetail(wallet.getValue(), more ? rows.subList(0, size) : rows, safePage, more);
    }

    @Transactional
    public ShopQr staticQr(User user, UUID sid, String rawCurrency) {
        sessions.merchant(user, sid);
        var shop = collecting(owner(user));
        String currency = CurrencyUtils.currency(rawCurrency);
        String account = walletNumber(shop, currency);
        var payment = payments.findFirstByAccountNumberAndQrTypeOrderByIdAsc(account, "STATIC").orElseGet(() -> {
            var qr = engine.generate(new QrCodeEngine.GenerateOptions(account, shop.name(), null, currency,
                    null, null, null, false));
            var saved = payments.saveAndFlush(Payment.builder().md5Hash(qr.getQrHash()).accountNumber(account)
                    .amount(BigDecimal.ZERO).currency(currency).qrString(qr.getQrString()).qrType("STATIC")
                    .status(PaymentStatus.PENDING).build());
            audit.successAs(user, "MERCHANT", "SHOP_QR_CREATED", saved.getId().toString());
            return saved;
        });
        return new ShopQr(payment.getQrString(), currency, account, shop.name(), shop.code());
    }

    @Transactional
    public CreatedRequest create(User user, UUID sid, String key, NewPaymentRequest request) {
        if (key == null || !key.matches("[A-Za-z0-9_-]{16,128}"))
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required");
        String currency = CurrencyUtils.currency(request.getCurrency());
        BigDecimal amount = CurrencyUtils.amount(request.getAmount(), currency, false);
        String orderReference = request.getOrderReference() == null || request.getOrderReference().isBlank() ? null
                : MerchantShopService.line(request.getOrderReference(), 50);
        sessions.merchant(user, sid);
        User owner = owner(user);
        String keyHash = HashUtils.sha256(key);
        String requestHash = HashUtils.sha256(String.join("\u001F", currency, amount.toPlainString(),
                Objects.toString(orderReference, "")));
        var prior = rows("WHERE r.owner_user_id=? AND r.key_hash=?", owner.getId(), keyHash);
        if (!prior.isEmpty()) {
            if (!prior.getFirst().requestHash().equals(requestHash)) throw new ApiException(HttpStatus.CONFLICT,
                    "IDEMPOTENCY_CONFLICT", "This request key was already used with different details");
            return new CreatedRequest(false, view(settle(prior.getFirst())));
        }
        var shop = collecting(owner);
        String account = walletNumber(shop, currency);
        String reference = reference();
        var qr = engine.generate(new QrCodeEngine.GenerateOptions(account, shop.name(), amount, currency,
                orderReference, reference, null, true));
        var payment = payments.saveAndFlush(Payment.builder().md5Hash(qr.getQrHash()).accountNumber(account)
                .amount(amount).currency(currency).qrString(qr.getQrString()).qrType("DYNAMIC")
                .status(PaymentStatus.PENDING).build());
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO merchant_payment_requests(id,merchant_id,owner_user_id,payment_id,account_number,currency,amount,
                    order_reference,reference,key_hash,request_hash,expires_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP + make_interval(secs => ?))
                """, id, shop.id(), owner.getId(), payment.getId(), account, currency, amount, orderReference, reference,
                keyHash, requestHash, Math.max(60, Math.min(ttlSeconds, 1800)));
        audit.successAs(owner, "MERCHANT", "PAYMENT_REQUEST_CREATED", reference);
        return new CreatedRequest(true, view(rows("WHERE r.id=?", id).getFirst()));
    }

    @Transactional
    public PaymentRequestView status(User user, UUID sid, UUID id) {
        sessions.merchant(user, sid);
        var shop = shops.requireShop(owner(user));
        var row = rows("WHERE r.id=? AND r.merchant_id=?", id, shop.id()).stream().findFirst()
                .orElseThrow(MerchantCollectionService::notFound);
        return view(settle(row));
    }

    @Transactional
    public PaymentRequestView cancel(User user, UUID sid, UUID id) {
        sessions.merchant(user, sid);
        var shop = shops.requireShop(owner(user));
        var row = rows("WHERE r.id=? AND r.merchant_id=?", id, shop.id()).stream().findFirst()
                .orElseThrow(MerchantCollectionService::notFound);
        lockPayment(row.paymentId());
        row = rows("WHERE r.id=? FOR UPDATE OF r", id).getFirst();
        if ("WAITING".equals(row.status())) {
            // An expired request is reported as expired; anything paid stays paid.
            boolean expired = !row.expiresAt().isAfter(OffsetDateTime.now());
            jdbc.update("UPDATE merchant_payment_requests SET status=?,completed_at=CURRENT_TIMESTAMP WHERE id=?",
                    expired ? "EXPIRED" : "CANCELLED", id);
            jdbc.update("UPDATE payments SET status='EXPIRED',updated_at=now() WHERE id=? AND status='PENDING'", row.paymentId());
            if (!expired) audit.successAs(user, "MERCHANT", "PAYMENT_REQUEST_CANCELLED", row.reference());
            row = rows("WHERE r.id=?", id).getFirst();
        }
        return view(row);
    }

    @Scheduled(fixedDelay = 60000, initialDelay = 90000)
    @Transactional
    public void expireWaiting() {
        var ids = jdbc.queryForList("""
                SELECT p.id FROM payments p JOIN merchant_payment_requests r ON r.payment_id=p.id
                WHERE r.status='WAITING' AND r.expires_at<=CURRENT_TIMESTAMP ORDER BY p.id LIMIT 200
                FOR UPDATE OF p SKIP LOCKED
                """, Long.class);
        for (Long paymentId : ids) {
            jdbc.update("""
                    UPDATE merchant_payment_requests SET status='EXPIRED',completed_at=CURRENT_TIMESTAMP
                    WHERE payment_id=? AND status='WAITING' AND expires_at<=CURRENT_TIMESTAMP
                    """, paymentId);
            jdbc.update("UPDATE payments SET status='EXPIRED',updated_at=now() WHERE id=? AND status='PENDING'", paymentId);
        }
    }

    /** Persists a lazy expiry under the payment-row lock; paid or terminal rows are returned as they are. */
    private RequestRow settle(RequestRow row) {
        if (!"WAITING".equals(row.status()) || row.expiresAt().isAfter(OffsetDateTime.now())) return row;
        lockPayment(row.paymentId());
        jdbc.update("""
                UPDATE merchant_payment_requests SET status='EXPIRED',completed_at=CURRENT_TIMESTAMP
                WHERE id=? AND status='WAITING' AND expires_at<=CURRENT_TIMESTAMP
                """, row.id());
        jdbc.update("UPDATE payments SET status='EXPIRED',updated_at=now() WHERE id=? AND status='PENDING'", row.paymentId());
        return rows("WHERE r.id=?", row.id()).getFirst();
    }

    private void lockPayment(long paymentId) {
        jdbc.queryForList("SELECT id FROM payments WHERE id=? FOR UPDATE", Long.class, paymentId);
    }

    private PaymentRequestView view(RequestRow row) {
        Receipt receipt = "PAID".equals(row.status())
                ? jdbc.query(COLLECTION_SQL + " WHERE c.payment_request_id=?", (r, i) -> collection(r), row.id())
                    .stream().findFirst().orElse(null)
                : null;
        String qr = "WAITING".equals(row.status())
                ? jdbc.queryForObject("SELECT qr_string FROM payments WHERE id=?", String.class, row.paymentId()) : null;
        return new PaymentRequestView(row.id(), row.reference(), row.status(), row.currency(),
                MerchantShopService.money(row.amount(), row.currency()), row.orderReference(), qr, row.createdAt(),
                row.expiresAt(), now(), receipt);
    }

    private List<RequestRow> rows(String where, Object... args) {
        return jdbc.query("""
                SELECT r.id,r.payment_id,r.reference,r.status,r.currency,r.amount,r.order_reference,r.created_at,
                    r.expires_at,r.request_hash FROM merchant_payment_requests r
                """ + where, (r, i) -> new RequestRow(r.getObject(1, UUID.class), r.getLong(2), r.getString(3),
                r.getString(4), r.getString(5), r.getBigDecimal(6), r.getString(7), r.getObject(8, OffsetDateTime.class),
                r.getObject(9, OffsetDateTime.class), r.getString(10)), args);
    }

    private static final String COLLECTION_SQL = """
            SELECT c.reference_number,c.currency,c.amount,c.paid_currency,c.paid_amount,c.payer_name,
                c.payer_account_masked,r.reference,r.order_reference,c.created_at
            FROM merchant_collections c LEFT JOIN merchant_payment_requests r ON r.id=c.payment_request_id
            """;

    private static Receipt collection(java.sql.ResultSet r) throws java.sql.SQLException {
        return new Receipt(r.getString(1), r.getString(2), MerchantShopService.money(r.getBigDecimal(3), r.getString(2)),
                r.getString(4), MerchantShopService.money(r.getBigDecimal(5), r.getString(4)), r.getString(6),
                r.getString(7), r.getString(8), r.getString(9), r.getObject(10, OffsetDateTime.class));
    }

    private MerchantShopService.OwnedShop collecting(User owner) {
        var shop = shops.requireShop(owner);
        if (!shop.active()) throw new ApiException(HttpStatus.FORBIDDEN, "MERCHANT_INACTIVE", "This shop cannot collect payments right now");
        return shop;
    }

    private String walletNumber(MerchantShopService.OwnedShop shop, String currency) {
        return jdbc.queryForList("""
                SELECT account_number FROM accounts WHERE merchant_id=? AND account_category='MERCHANT' AND currency=?
                    AND status='ACTIVE'
                """, String.class, shop.id(), currency).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.CONFLICT, "MERCHANT_WALLET_UNAVAILABLE",
                        "This business wallet is not available"));
    }

    private String reference() {
        for (int attempt = 0; attempt < 20; attempt++) {
            var code = new StringBuilder("PR");
            for (int i = 0; i < 10; i++) code.append(CODE_ALPHABET.charAt(RANDOM.nextInt(CODE_ALPHABET.length())));
            if (jdbc.queryForObject("SELECT count(*) FROM merchant_payment_requests WHERE reference=?", Long.class,
                    code.toString()) == 0) return code.toString();
        }
        throw new IllegalStateException("Payment reference allocation failed");
    }

    private User owner(User user) {
        return users.findById(user.getId()).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                "SESSION_INVALID", "Session is expired or revoked"));
    }

    private static LocalDate today() { return LocalDate.now(BUSINESS_ZONE); }
    private static OffsetDateTime now() { return OffsetDateTime.now(); }
    private static ResourceNotFoundException notFound() { return new ResourceNotFoundException("Not available"); }
}
