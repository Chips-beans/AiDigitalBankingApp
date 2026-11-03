package com.bank.digital_banking.module.merchant.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.Locale;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Internal-pilot activation: self-service shops start ACTIVE only in local/dev/test.
 * Elsewhere they start PENDING for staff review. This is not business verification.
 */
@Component
public class MerchantOnboardingPolicy {
    private final boolean activateOnRegistration;

    public MerchantOnboardingPolicy(Environment environment,
            @Value("${app.merchant.self-service-activation:#{null}}") Boolean configured) {
        Set<String> profiles = Arrays.stream(environment.getActiveProfiles())
                .map(p -> p.toLowerCase(Locale.ROOT)).collect(Collectors.toSet());
        boolean production = profiles.contains("prod") || profiles.contains("production");
        boolean development = !production && profiles.stream().anyMatch(Set.of("local", "dev", "test")::contains);
        if (Boolean.TRUE.equals(configured) && !development)
            throw new IllegalStateException("Self-service shop activation is limited to local, dev and test profiles");
        this.activateOnRegistration = configured == null ? development : configured;
    }

    public String initialStatus() { return activateOnRegistration ? "ACTIVE" : "PENDING"; }
}
