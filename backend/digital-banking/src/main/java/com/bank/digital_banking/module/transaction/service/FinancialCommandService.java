package com.bank.digital_banking.module.transaction.service;

import com.bank.digital_banking.common.util.TransactionLockPolicy;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.util.CurrencyUtils;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.transaction.dto.TransactionResponseDto;
import com.bank.digital_banking.module.transaction.entity.TransactionType;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.util.Arrays;

@Service
@RequiredArgsConstructor
public class FinancialCommandService {
    private final JdbcTemplate jdbc;
    private final ObjectMapper json;
    private final FinancialPostingService posting;
    private final TransactionLockPolicy locks;

    @Transactional(isolation = org.springframework.transaction.annotation.Isolation.READ_COMMITTED)
    public TransactionResponseDto execute(User actor, TransactionType operation, String key, String source,
                                          String destination, BigDecimal amount, String currency, String remark) {
        return executeNamed(actor, operation, operation.name(), key, source, destination, amount, currency, remark);
    }

    @Transactional(isolation = org.springframework.transaction.annotation.Isolation.READ_COMMITTED)
    public TransactionResponseDto executeQr(User actor, String key, String source, String destination,
                                             BigDecimal amount, String currency, String remark) {
        return executeNamed(actor, TransactionType.TRANSFER, "QR_TRANSFER", key, source, destination, amount, currency, remark);
    }

    private TransactionResponseDto executeNamed(User actor, TransactionType operation, String namespace, String key,
            String source, String destination, BigDecimal amount, String currency, String remark) {
        if (actor == null || actor.getId() == null) throw new AccessDeniedException("An authenticated actor is required");
        if (operation != TransactionType.TRANSFER && operation != TransactionType.DEPOSIT)
            throw new IllegalArgumentException("Unsupported financial operation");
        boolean allowed = actor.getRoles().stream().anyMatch(role -> operation == TransactionType.TRANSFER
                ? role.getName() == ERole.ROLE_CUSTOMER
                : role.getName() == ERole.ROLE_ADMIN || role.getName() == ERole.ROLE_BANK_EMPLOYEE);
        if (!allowed) throw new AccessDeniedException("Operation is not permitted for this role");
        if (key == null || !key.matches("[A-Za-z0-9._:-]{1,128}"))
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_REQUIRED", "Provide an Idempotency-Key of 1-128 letters, digits, dots, underscores, colons or hyphens");
        currency = CurrencyUtils.currency(currency);
        amount = CurrencyUtils.amount(amount, currency, false);
        if (destination == null || !destination.matches("[0-9]{10,20}")
                || (operation == TransactionType.TRANSFER && (source == null || !source.matches("[0-9]{10,20}") || source.equals(destination)))
                || (remark != null && remark.length() > 255))
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Invalid accounts or remark");
        String fingerprint = HashUtils.sha256(json.writeValueAsString(Arrays.asList(source, destination,
                amount.stripTrailingZeros().toPlainString(), currency, remark)));
        locks.apply();
        // PostgreSQL waits for an in-flight claim; a failed command rolls its claim back.
        jdbc.update("""
                INSERT INTO idempotency_records(actor_user_id, operation, request_key, request_hash)
                VALUES (?, ?, ?, ?) ON CONFLICT (actor_user_id, operation, request_key) DO NOTHING
                """, actor.getId(), namespace, key, fingerprint);
        var claim = jdbc.queryForMap("""
                SELECT id, request_hash, transaction_id, response_json FROM idempotency_records
                WHERE actor_user_id = ? AND operation = ? AND request_key = ? FOR UPDATE
                """, actor.getId(), namespace, key);
        if (!fingerprint.equals(claim.get("request_hash")))
            throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_CONFLICT", "This key was already used with a different request");
        if (claim.get("transaction_id") != null)
            return json.readValue((String) claim.get("response_json"), TransactionResponseDto.class);
        var result = posting.post(actor, operation, source, destination, amount, currency, remark);
        var response = TransactionResponseDto.fromEntity(result);
        jdbc.update("UPDATE idempotency_records SET transaction_id = ?, response_json = ? WHERE id = ?",
                result.getId(), json.writeValueAsString(response), claim.get("id"));
        return response;
    }
}
