package com.bank.digital_banking.module.merchant.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.merchant.MerchantAuthService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Isolation;

import java.nio.charset.StandardCharsets;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;

import static com.bank.digital_banking.module.merchant.dto.MerchantCollectionDtos.*;
import static com.bank.digital_banking.module.merchant.service.MerchantCollectionService.*;

/** Read models of confirmed QR credits only. No ledger writes or live-profile receipt fields. */
@Service @RequiredArgsConstructor
public class MerchantSalesService {
    private final JdbcTemplate jdbc;
    private final MerchantAuthService sessions;
    private final MerchantShopService shops;
    private final MerchantCollectionService collections;

    public record Sales(List<Receipt> items, String nextCursor, List<Totals> totals) {}
    public record Bucket(String bucket, String currency, long count, String gross) {}
    public record Report(String period, String from, String to, List<Bucket> buckets, List<Totals> totals) {}
    public record RequestItem(UUID requestId, String reference, String status, String currency, String amount,
                              String orderReference, OffsetDateTime createdAt, OffsetDateTime expiresAt) {}
    public record Requests(List<RequestItem> items, String nextCursor) {}
    private record Point(OffsetDateTime at, String id) {}
    private record SaleRow(Receipt receipt, long id) {}
    private record Range(LocalDate from, LocalDate to) {
        OffsetDateTime start() { return from.atStartOfDay(BUSINESS_ZONE).toOffsetDateTime(); }
        OffsetDateTime end() { return to.plusDays(1).atStartOfDay(BUSINESS_ZONE).toOffsetDateTime(); }
    }

    // Page and whole-filter totals share a database snapshot even if a customer
    // confirms another payment between the two SELECTs.
    @Transactional(isolation = Isolation.REPEATABLE_READ)
    public Sales sales(User user, UUID sid, String from, String to, String currency, String q, String cursor, int size) {
        sessions.merchant(user, sid);
        var shop = shops.requireShop(user);
        var range = range(from, to, 366);
        size(size);
        if (currency != null && !Set.of("KHR", "USD").contains(currency)) throw invalid();
        if (q != null && (q.isBlank() || q.length() > 50 || q.codePoints().anyMatch(Character::isISOControl))) throw invalid();
        var args = new ArrayList<Object>(List.of(shop.id(), range.start(), range.end()));
        String filter = " WHERE c.merchant_id=? AND c.created_at>=? AND c.created_at<?";
        if (currency != null) { filter += " AND c.currency=?"; args.add(currency); }
        if (q != null) {
            // LIKE metacharacters are literal user text, never wildcard privileges.
            String literal = q.toLowerCase(Locale.ROOT).replace("!", "!!").replace("%", "!%").replace("_", "!_");
            filter += " AND (lower(c.reference_number) LIKE ? ESCAPE '!' OR lower(r.reference) LIKE ? ESCAPE '!' OR lower(r.order_reference) LIKE ? ESCAPE '!')";
            args.add("%" + literal); args.add("%" + literal + "%"); args.add("%" + literal + "%");
        }
        var totals = totals(filter, args);
        var point = decode(cursor, false);
        if (point != null) { filter += " AND (c.created_at,c.transaction_id)<(?,?)"; args.add(point.at()); args.add(Long.parseLong(point.id())); }
        args.add(size + 1);
        var rows = jdbc.query(COLLECTION_SQL + filter + " ORDER BY c.created_at DESC,c.transaction_id DESC LIMIT ?",
                (r, i) -> new SaleRow(collection(r), r.getLong(11)), args.toArray());
        boolean more = rows.size() > size;
        var page = more ? rows.subList(0, size) : rows;
        var last = page.isEmpty() ? null : page.getLast();
        return new Sales(page.stream().map(SaleRow::receipt).toList(), more ? encode(last.receipt().paidAt(), "" + last.id()) : null, totals);
    }

    @Transactional
    public Receipt receipt(User user, UUID sid, String reference) {
        sessions.merchant(user, sid);
        var shop = shops.requireShop(user);
        if (reference.length() > 36) throw new ResourceNotFoundException("Not available");
        return jdbc.query(COLLECTION_SQL + " WHERE c.merchant_id=? AND c.reference_number=?", (r, i) -> collection(r), shop.id(), reference)
                .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Not available"));
    }

    @Transactional(isolation = Isolation.REPEATABLE_READ)
    public Report report(User user, UUID sid, String period, String from, String to) {
        sessions.merchant(user, sid);
        var shop = shops.requireShop(user);
        if (!Set.of("DAY", "MONTH").contains(period)) throw invalid();
        var range = range(from, to, period.equals("DAY") ? 92 : 732);
        if (period.equals("MONTH") && ChronoUnit.MONTHS.between(YearMonth.from(range.from()), YearMonth.from(range.to())) >= 24) throw invalid();
        var args = new ArrayList<Object>(List.of(shop.id(), range.start(), range.end()));
        String filter = " WHERE c.merchant_id=? AND c.created_at>=? AND c.created_at<?";
        // period is an allowlisted literal; all request values stay bound parameters.
        var grouped = jdbc.query("SELECT date_trunc('" + period.toLowerCase(Locale.ROOT) + "', c.created_at AT TIME ZONE 'Asia/Phnom_Penh')::date,c.currency,count(*),sum(c.amount) FROM merchant_collections c" + filter + " GROUP BY 1,2",
                (r, i) -> new Bucket(period.equals("DAY") ? r.getDate(1).toLocalDate().toString() : YearMonth.from(r.getDate(1).toLocalDate()).toString(),
                        r.getString(2), r.getLong(3), MerchantShopService.money(r.getBigDecimal(4), r.getString(2))), args.toArray());
        var indexed = new HashMap<String, Bucket>();
        grouped.forEach(b -> indexed.put(b.bucket() + b.currency(), b));
        var buckets = new ArrayList<Bucket>();
        LocalDate at = period.equals("DAY") ? range.from() : range.from().withDayOfMonth(1);
        for (; !at.isAfter(range.to()); at = period.equals("DAY") ? at.plusDays(1) : at.plusMonths(1)) {
            String key = period.equals("DAY") ? at.toString() : YearMonth.from(at).toString();
            for (String c : List.of("KHR", "USD")) buckets.add(indexed.getOrDefault(key + c, new Bucket(key, c, 0, c.equals("KHR") ? "0" : "0.00")));
        }
        return new Report(period, range.from().toString(), range.to().toString(), buckets, totals(filter, args));
    }

    @Transactional
    public Requests requests(User user, UUID sid, String status, String cursor, int size) {
        sessions.merchant(user, sid);
        var shop = shops.requireShop(user);
        size(size);
        if (status != null && !Set.of("WAITING", "PAID", "EXPIRED", "CANCELLED").contains(status)) throw invalid();
        var point = decode(cursor, true);
        var args = new ArrayList<Object>(List.of(shop.id()));
        String filter = "WHERE r.merchant_id=?";
        // Filter by effective expiry, including rows not yet persisted by the bounded
        // lazy batch or sweep. Never return a due request in the WAITING filter.
        if ("WAITING".equals(status)) filter += " AND r.status='WAITING' AND r.expires_at>CURRENT_TIMESTAMP";
        else if ("EXPIRED".equals(status)) filter += " AND (r.status='EXPIRED' OR (r.status='WAITING' AND r.expires_at<=CURRENT_TIMESTAMP))";
        else if (status != null) { filter += " AND r.status=?"; args.add(status); }
        if (point != null) { filter += " AND (r.created_at,r.id)<(?,?)"; args.add(point.at()); args.add(UUID.fromString(point.id())); }
        args.add(size + 1);
        var rows = collections.rows(filter + " ORDER BY r.created_at DESC,r.id DESC LIMIT ?", args.toArray());
        boolean more = rows.size() > size;
        var page = more ? rows.subList(0, size) : rows;
        var asOf = jdbc.queryForObject("SELECT CURRENT_TIMESTAMP", OffsetDateTime.class);
        // Reserve the 50-row budget for every due row that will be mapped first;
        // fill the remaining budget with the oldest due payment IDs. The union
        // is bounded too, so page settling cannot silently exceed the cap.
        var batch = new TreeMap<Long, RequestRow>();
        for (var row : page) if ("WAITING".equals(row.status()) && !row.expiresAt().isAfter(asOf)) batch.put(row.paymentId(), row);
        var expired = collections.rows("WHERE r.merchant_id=? AND r.status='WAITING' AND r.expires_at<=CURRENT_TIMESTAMP ORDER BY r.payment_id LIMIT 50", shop.id());
        for (var row : expired) if (batch.size() < 50) batch.putIfAbsent(row.paymentId(), row);
        var settled = new HashMap<UUID, RequestRow>();
        // Keep the existing payment-first lock order, ascending across the batch.
        for (var row : batch.values()) settled.put(row.id(), collections.settle(row));
        page = page.stream().map(row -> settled.getOrDefault(row.id(), row)).toList();
        var last = page.isEmpty() ? null : page.getLast();
        return new Requests(page.stream().map(r -> new RequestItem(r.id(), r.reference(), r.status(), r.currency(),
                MerchantShopService.money(r.amount(), r.currency()), r.orderReference(), r.createdAt(), r.expiresAt())).toList(),
                more ? encode(last.createdAt(), last.id().toString()) : null);
    }

    private List<Totals> totals(String filter, List<Object> args) {
        var found = jdbc.query("SELECT c.currency,count(*),sum(c.amount) FROM merchant_collections c LEFT JOIN merchant_payment_requests r ON r.id=c.payment_request_id" + filter + " GROUP BY c.currency",
                (r, i) -> new Totals(r.getString(1), r.getLong(2), MerchantShopService.money(r.getBigDecimal(3), r.getString(1))), args.toArray());
        return List.of("KHR", "USD").stream().map(c -> found.stream().filter(t -> t.currency().equals(c)).findFirst()
                .orElse(new Totals(c, 0, c.equals("KHR") ? "0" : "0.00"))).toList();
    }

    private static Range range(String from, String to, int maxDays) {
        try {
            var today = LocalDate.now(BUSINESS_ZONE);
            var start = from == null ? today : LocalDate.parse(from);
            var end = to == null ? today : LocalDate.parse(to);
            if (start.getYear() < 1 || end.getYear() > 9998 || start.isAfter(end) || ChronoUnit.DAYS.between(start, end) >= maxDays) throw invalid();
            return new Range(start, end);
        } catch (DateTimeException e) { throw invalid(); }
    }
    private static void size(int size) { if (size < 1 || size > 50) throw invalid(); }
    private static String encode(OffsetDateTime at, String id) {
        long micros = Math.addExact(Math.multiplyExact(at.toEpochSecond(), 1_000_000), at.getNano() / 1000);
        return Base64.getUrlEncoder().withoutPadding().encodeToString((micros + ":" + id).getBytes(StandardCharsets.UTF_8));
    }
    private static Point decode(String cursor, boolean uuid) {
        if (cursor == null) return null;
        try {
            if (cursor.length() > 128 || !cursor.matches("[A-Za-z0-9_-]+")) throw invalid();
            String decoded = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8);
            String[] parts = decoded.split(":", -1);
            if (parts.length != 2 || !parts[0].matches("-?[0-9]{1,18}")) throw invalid();
            long micros = Long.parseLong(parts[0]);
            if (uuid) { if (!UUID.fromString(parts[1]).toString().equals(parts[1])) throw invalid(); }
            else if (!parts[1].matches("[1-9][0-9]{0,18}") || Long.parseLong(parts[1]) < 1) throw invalid();
            var at = Instant.ofEpochSecond(Math.floorDiv(micros, 1_000_000), Math.floorMod(micros, 1_000_000) * 1000).atOffset(ZoneOffset.UTC);
            if (!encode(at, parts[1]).equals(cursor)) throw invalid();
            return new Point(at, parts[1]);
        } catch (IllegalArgumentException | DateTimeException | ArithmeticException e) { throw invalid(); }
    }
    private static ApiException invalid() { return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_SALES_FILTER", "Check the dates, filters and cursor"); }
}
