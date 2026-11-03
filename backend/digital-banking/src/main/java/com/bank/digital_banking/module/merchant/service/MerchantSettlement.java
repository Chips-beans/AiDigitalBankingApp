package com.bank.digital_banking.module.merchant.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.account.entity.AccountCategory;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.transaction.dto.TransactionResponseDto;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.Objects;
import java.util.UUID;

/**
 * Merchant rules inside the Customer QR payment path (M6): verified shop identity,
 * collection status, payment-request validity and the confirmed collection snapshot.
 * Called after the registered payment row is locked, so request state is serialized
 * against merchant cancellation.
 */
@Component @RequiredArgsConstructor
public class MerchantSettlement {
    private final JdbcTemplate jdbc;

    public record Payee(long merchantId, String merchantCode, String storeName, String categoryCode,
                        String status, boolean hasLogo) {
        public boolean active() { return "ACTIVE".equals(status); }
    }

    public record Request(UUID id, String status, OffsetDateTime expiresAt, String reference, String orderReference) {}

    /** The verified shop behind a business wallet, or null for a personal wallet. */
    public Payee payee(Account account) {
        if (account.getAccountCategory() != AccountCategory.MERCHANT || account.getMerchantId() == null) return null;
        return jdbc.query("""
                SELECT m.id,m.merchant_id,m.store_name,m.category_code,m.status::text,
                    EXISTS(SELECT 1 FROM merchant_logos l WHERE l.merchant_id=m.id AND l.status='ATTACHED')
                FROM merchants m WHERE m.id=?
                """, (r, i) -> new Payee(r.getLong(1), r.getString(2), r.getString(3), r.getString(4),
                r.getString(5), r.getBoolean(6)), account.getMerchantId()).stream().findFirst()
                .orElseThrow(MerchantSettlement::inactive);
    }

    /** Suspended, pending or inactive shops cannot receive QR payments. */
    public void requireCollecting(Payee payee) {
        if (payee != null && !payee.active()) throw inactive();
    }

    public Request request(long paymentId, boolean lock) {
        return jdbc.query("SELECT id,status,expires_at,reference,order_reference FROM merchant_payment_requests WHERE payment_id=?"
                        + (lock ? " FOR UPDATE" : ""),
                (r, i) -> new Request(r.getObject(1, UUID.class), r.getString(2), r.getObject(3, OffsetDateTime.class),
                        r.getString(4), r.getString(5)), paymentId).stream().findFirst().orElse(null);
    }

    public void requirePayable(Request request) {
        if (request == null) return;
        switch (request.status()) {
            case "PAID" -> throw new ApiException(HttpStatus.CONFLICT, "PAYMENT_ALREADY_COMPLETED", "This request has already been paid");
            case "CANCELLED" -> throw new ApiException(HttpStatus.CONFLICT, "PAYMENT_REQUEST_CANCELLED", "The shop cancelled this payment request");
            default -> {
                if (!"WAITING".equals(request.status()) || !request.expiresAt().isAfter(OffsetDateTime.now()))
                    throw new ApiException(HttpStatus.CONFLICT, "PAYMENT_REQUEST_EXPIRED", "This payment request has expired; ask the shop for a new QR");
            }
        }
    }

    /** Snapshots a confirmed QR credit to a business wallet; marks its request paid. */
    @Transactional(propagation = Propagation.MANDATORY)
    public void record(Payee payee, Request request, Account destination, Account source, User payer,
                       TransactionResponseDto transaction) {
        if (payee == null) return;
        jdbc.update("""
                INSERT INTO merchant_collections(transaction_id,merchant_id,account_number,currency,amount,paid_currency,
                    paid_amount,exchange_rate,reference_number,payment_request_id,store_name,payer_name,payer_account_masked)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, transaction.getId(), payee.merchantId(), destination.getAccountNumber(), destination.getCurrency(),
                transaction.getCreditAmount(), transaction.getCurrency(), transaction.getAmount(), transaction.getExchangeRate(),
                transaction.getReferenceNumber(), request == null ? null : request.id(), payee.storeName(),
                payerName(payer), mask(source.getAccountNumber()));
        if (request != null) {
            int updated = jdbc.update("""
                    UPDATE merchant_payment_requests SET status='PAID',transaction_id=?,completed_at=CURRENT_TIMESTAMP
                    WHERE id=? AND status='WAITING'
                    """, transaction.getId(), request.id());
            if (updated != 1) throw new IllegalStateException("Payment request changed during settlement");
        }
    }

    /** First name only: enough for a cashier to recognise a payer, nothing more. */
    static String payerName(User payer) {
        String first = Objects.toString(payer.getFirstName(), "").strip();
        if (first.isEmpty()) first = "Kesor customer";
        return first.length() > 100 ? first.substring(0, 100) : first;
    }

    public static String mask(String number) {
        return number == null || number.length() < 4 ? "••••" : "•••• " + number.substring(number.length() - 4);
    }

    private static ApiException inactive() {
        return new ApiException(HttpStatus.CONFLICT, "MERCHANT_INACTIVE", "This shop cannot accept payments right now");
    }
}
