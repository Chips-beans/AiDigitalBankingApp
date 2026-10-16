package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.repository.LoginAttemptLimitRepository;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.Duration;
import java.time.OffsetDateTime;

@Service
@RequiredArgsConstructor
public class LoginAttemptService {
    private final LoginAttemptLimitRepository limits;
    @Value("${app.login.max-attempts:10}") private int maxAttempts;
    @Value("${app.login.window-minutes:15}") private int windowMinutes;

    @PostConstruct
    void validateConfiguration() {
        if (maxAttempts < 1 || windowMinutes < 1) {
            throw new IllegalArgumentException("Login limits must be positive");
        }
    }

    // Commit before password verification, so rejected logins cannot roll back the counter.
    @Transactional
    public void recordAttempt(String key) {
        limits.ensureExists(key);
        var limit = limits.findLockedById(key).orElseThrow();
        OffsetDateTime now = OffsetDateTime.now();
        if (!now.isBefore(limit.getWindowStartedAt().plusMinutes(windowMinutes))) {
            limit.setWindowStartedAt(now);
            limit.setAttemptCount(0);
        }
        if (limit.getAttemptCount() >= maxAttempts) {
            long retry = Math.max(1L, (Duration.between(now,
                    limit.getWindowStartedAt().plusMinutes(windowMinutes)).toMillis() + 999) / 1000);
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "LOGIN_RATE_LIMITED",
                    "Too many sign-in attempts; try again later", retry);
        }
        limit.setAttemptCount(limit.getAttemptCount() + 1);
        limits.save(limit);
    }
}
