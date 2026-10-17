package com.bank.digital_banking.common.util;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Component
public class TransactionLockPolicy {
    private final JdbcTemplate jdbc;
    private final int timeoutMs;

    public TransactionLockPolicy(JdbcTemplate jdbc, @Value("${app.financial.lock-timeout-ms:5000}") int timeoutMs) {
        if (timeoutMs < 50 || timeoutMs > 60000)
            throw new IllegalArgumentException("Financial lock timeout must be between 50 and 60000 milliseconds");
        this.jdbc = jdbc;
        this.timeoutMs = timeoutMs;
    }

    @Transactional(propagation = Propagation.MANDATORY)
    public void apply() {
        // Transaction-local: pooled connections return to their original configuration on completion.
        jdbc.queryForObject("select set_config('lock_timeout', ?, true)", String.class, timeoutMs + "ms");
    }
}
