package com.bank.digital_banking.module.auth.merchant;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.*;
import org.springframework.transaction.annotation.Transactional;

/** Bounded sweeps remove recovery secrets promptly and old attempts/budgets after one day. */
@Configuration @EnableScheduling @RequiredArgsConstructor
public class MerchantAuthRetention {
    private final JdbcTemplate jdbc;
    @Scheduled(fixedDelay=60000, initialDelay=60000)
    @Transactional
    public void sweep() {
        jdbc.update("""
            UPDATE merchant_auth_attempts SET recovery_ciphertext=NULL,recovery_expires_at=NULL
            WHERE id IN (SELECT id FROM merchant_auth_attempts WHERE recovery_expires_at<=CURRENT_TIMESTAMP
                         LIMIT 200 FOR UPDATE SKIP LOCKED)
            """);
        jdbc.update("""
            UPDATE merchant_auth_attempts SET status='EXPIRED'
            WHERE id IN (SELECT id FROM merchant_auth_attempts WHERE status IN ('PENDING','APPROVED')
                         AND expires_at<=CURRENT_TIMESTAMP LIMIT 200 FOR UPDATE SKIP LOCKED)
            """);
        jdbc.update("DELETE FROM merchant_auth_attempts WHERE id IN (SELECT id FROM merchant_auth_attempts WHERE expires_at<CURRENT_TIMESTAMP-INTERVAL '1 day' LIMIT 200 FOR UPDATE SKIP LOCKED)");
        jdbc.update("DELETE FROM merchant_auth_limits WHERE id IN (SELECT id FROM merchant_auth_limits WHERE window_start<CURRENT_TIMESTAMP-INTERVAL '1 day' LIMIT 200 FOR UPDATE SKIP LOCKED)");
    }
}
