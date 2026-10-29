package com.bank.digital_banking.config;

import com.bank.digital_banking.module.auth.entity.ERole;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.repository.RoleRepository;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.Set;

/** Explicit local QA identity, independent of the existing demo users/balances. */
@Component
@Profile("local & !prod")
@ConditionalOnProperty(name = "app.dev.qa-staff.enabled", havingValue = "true")
@RequiredArgsConstructor
public class LocalQaStaffData implements ApplicationRunner {
    private final UserRepository users;
    private final RoleRepository roles;
    private final PasswordEncoder encoder;
    @Value("${app.dev.qa-staff.username:}") private String username;
    @Value("${app.dev.qa-staff.email:}") private String email;
    @Value("${app.dev.qa-staff.password:}") private String password;

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (!username.matches("[A-Za-z0-9_.-]{3,50}")
                || email.length() > 100 || !email.equals(email.trim().toLowerCase(java.util.Locale.ROOT))
                || !email.matches("[^\\s@]+@[^\\s@]+\\.[^\\s@]+")
                || password.length() < 12 || password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 72
                || password.startsWith("replace_")) {
            throw new IllegalArgumentException("Configure a valid separate local QA staff identity and password");
        }
        var existing = users.findByUsername(username);
        if (existing.isPresent()) {
            var user = existing.get();
            if (!user.getEmail().equals(email) || !user.isEnabled()
                    || user.getRoles().size() != 1 || user.getRoles().stream().noneMatch(
                    role -> role.getName() == ERole.ROLE_BANK_EMPLOYEE)
                    || !encoder.matches(password, user.getPassword())) {
                throw new IllegalStateException("Local QA staff identity conflicts with an existing user; no user was modified");
            }
            return;
        }
        if (users.findByEmail(email).isPresent()) {
            throw new IllegalStateException("Local QA staff email already belongs to a user; no user was modified");
        }
        var employee = roles.findByName(ERole.ROLE_BANK_EMPLOYEE).orElseThrow();
        users.save(User.builder().username(username).email(email).password(encoder.encode(password))
                .enabled(true).roles(Set.of(employee)).build());
    }
}
