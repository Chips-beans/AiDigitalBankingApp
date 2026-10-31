package com.bank.digital_banking.module.auth.merchant;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.util.HashUtils;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;

/** Database-atomic budgets persist across failed requests, restarts and server instances. */
@Service @RequiredArgsConstructor
public class MerchantAuthRateLimiter {
    private final JdbcTemplate jdbc;
    @Transactional(propagation=Propagation.REQUIRES_NEW, noRollbackFor=ApiException.class)
    public void check(String lane, String identity, int maximum) {
        String id = lane + ":" + HashUtils.sha256(identity);
        int hits = jdbc.queryForObject("""
            INSERT INTO merchant_auth_limits(id,window_start,hits) VALUES (?,CURRENT_TIMESTAMP,1)
            ON CONFLICT(id) DO UPDATE SET
                hits=CASE WHEN merchant_auth_limits.window_start <= CURRENT_TIMESTAMP - INTERVAL '1 minute'
                          THEN 1 ELSE merchant_auth_limits.hits+1 END,
                window_start=CASE WHEN merchant_auth_limits.window_start <= CURRENT_TIMESTAMP - INTERVAL '1 minute'
                          THEN CURRENT_TIMESTAMP ELSE merchant_auth_limits.window_start END
            RETURNING hits
            """, Integer.class, id);
        if (hits > maximum) throw new ApiException(HttpStatus.TOO_MANY_REQUESTS,
                "MERCHANT_AUTH_RATE_LIMITED", "Too many requests; try again shortly", 60L);
    }
}
