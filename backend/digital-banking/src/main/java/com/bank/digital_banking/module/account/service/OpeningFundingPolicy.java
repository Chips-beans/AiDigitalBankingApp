package com.bank.digital_banking.module.account.service;

import com.bank.digital_banking.module.account.dto.AccountPairDtos;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;
import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Locale;
import java.util.Set;

@Component
public class OpeningFundingPolicy {
    private final boolean enabled;
    public OpeningFundingPolicy(Environment environment,
            @Value("${app.dev.opening-funding.enabled:false}") boolean enabled) {
        Set<String> profiles = Arrays.stream(environment.getActiveProfiles())
                .map(p -> p.toLowerCase(Locale.ROOT)).collect(java.util.stream.Collectors.toSet());
        if (enabled && (profiles.contains("prod") || profiles.contains("production")
                || profiles.stream().noneMatch(Set.of("local", "dev", "test", "staging")::contains))) {
            throw new IllegalStateException("Test opening funding requires an explicit non-production profile and cannot run in production");
        }
        this.enabled = enabled;
    }
    public boolean enabled() { return enabled; }
    public BigDecimal amount(String currency) {
        return enabled ? new BigDecimal("USD".equals(currency) ? "200.00" : "100000") : BigDecimal.ZERO;
    }
    public AccountPairDtos.Policy response() {
        return new AccountPairDtos.Policy(enabled, amount("USD"), amount("KHR"));
    }
}
