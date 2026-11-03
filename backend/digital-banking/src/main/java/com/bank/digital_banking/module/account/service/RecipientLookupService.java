package com.bank.digital_banking.module.account.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.account.entity.AccountStatus;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.service.ProfilePhotoService;
import com.bank.digital_banking.module.transaction.dto.TransactionResponseDto;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import java.time.OffsetDateTime;
import java.util.Base64;

/**
 * Resolves an account number to its holder's profile name and photo so customers can
 * confirm who they are paying. Only active accounts resolve; everything else is the same
 * 404, and lookups are rate limited and audited to limit enumeration.
 */
@Service
@RequiredArgsConstructor
public class RecipientLookupService {
    private final AccountRepository accounts;
    private final JdbcTemplate jdbc;
    private final AuditTrail audit;
    @Value("${app.recipient-lookup.max-per-window:120}") private int maxPerWindow;
    @Value("${app.recipient-lookup.window-minutes:15}") private int windowMinutes;

    private final org.springframework.transaction.PlatformTransactionManager transactions;

    public record Recipient(String accountNumber, String currency, String displayName, boolean hasPhoto) {}

    public Recipient lookup(User actor, String number) {
        validate(number);
        limit(actor);
        return read().execute(status -> {
            Account account = resolve(number);
            boolean photo = Boolean.TRUE.equals(jdbc.queryForObject(
                    "SELECT EXISTS(SELECT 1 FROM customer_profile_photos WHERE user_id=?)", Boolean.class, account.getUser().getId()));
            audit.successAs(actor, "ACCOUNT", "RECIPIENT_LOOKUP", mask(account.getAccountNumber()));
            return new Recipient(account.getAccountNumber(), account.getCurrency(),
                    TransactionResponseDto.displayName(account.getUser()), photo);
        });
    }

    public ProfilePhotoService.Photo photo(User actor, String number) {
        validate(number);
        limit(actor);
        return read().execute(status -> {
            Account account = resolve(number);
            return jdbc.query("SELECT content_type, image_data FROM customer_profile_photos WHERE user_id = ?",
                            (row, index) -> new ProfilePhotoService.Photo(row.getString(1),
                                    Base64.getEncoder().encodeToString(row.getBytes(2))), account.getUser().getId())
                    .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Photo not available"));
        });
    }

    private static void validate(String number) {
        if (number == null || !number.matches("[0-9]{10,20}"))
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_ACCOUNT_NUMBER", "Enter a 10 to 20 digit account number");
    }

    private Account resolve(String number) {
        return accounts.findByAccountNumber(number)
                .filter(a -> a.getStatus() == AccountStatus.ACTIVE)
                // Shops are paid by QR; a business wallet number never reveals its owner.
                .filter(a -> a.getAccountCategory() != com.bank.digital_banking.module.account.entity.AccountCategory.MERCHANT)
                .orElseThrow(() -> new ResourceNotFoundException("Account not available"));
    }

    // Not read-only: the lookup audit row is written in the same transaction.
    private org.springframework.transaction.support.TransactionTemplate read() {
        return new org.springframework.transaction.support.TransactionTemplate(transactions);
    }

    // Committed before the lookup itself, so rejected lookups still count.
    private void limit(User actor) {
        new org.springframework.transaction.support.TransactionTemplate(transactions).executeWithoutResult(status -> count(actor));
    }

    private void count(User actor) {
        String key = "recipient-lookup:" + actor.getId();
        jdbc.update("INSERT INTO login_attempt_limits(id,window_started_at,attempt_count) VALUES (?,CURRENT_TIMESTAMP,0) ON CONFLICT (id) DO NOTHING", key);
        var row = jdbc.queryForObject("SELECT window_started_at, attempt_count FROM login_attempt_limits WHERE id=? FOR UPDATE",
                (rs, index) -> java.util.Map.entry(rs.getObject(1, OffsetDateTime.class), rs.getInt(2)), key);
        OffsetDateTime started = row.getKey();
        int count = row.getValue();
        if (!OffsetDateTime.now().isBefore(started.plusMinutes(windowMinutes))) {
            jdbc.update("UPDATE login_attempt_limits SET window_started_at=CURRENT_TIMESTAMP, attempt_count=1 WHERE id=?", key);
            return;
        }
        if (count >= maxPerWindow) {
            long retry = Math.max(1L, java.time.Duration.between(OffsetDateTime.now(), started.plusMinutes(windowMinutes)).toSeconds());
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "LOOKUP_RATE_LIMITED", "Too many recipient lookups; try again later", retry);
        }
        jdbc.update("UPDATE login_attempt_limits SET attempt_count=attempt_count+1 WHERE id=?", key);
    }

    private static String mask(String number) {
        return "******" + number.substring(number.length() - 4);
    }
}
