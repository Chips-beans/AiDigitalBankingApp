package com.bank.digital_banking.config;

import com.bank.digital_banking.module.account.entity.*;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.util.Set;

@Component @Profile("local & !prod")
@ConditionalOnProperty(name="app.dev.seed.enabled", havingValue="true")
@RequiredArgsConstructor
public class LocalDevelopmentData implements ApplicationRunner {
    private final UserRepository users;
    private final RoleRepository roles;
    private final AccountRepository accounts;
    private final PasswordEncoder encoder;
    @Value("${app.dev.seed.password}") private String password;

    @Override @Transactional
    public void run(ApplicationArguments args) {
        if (password.length() < 12 || password.startsWith("replace_"))
            throw new IllegalArgumentException("Set a local demo password of at least 12 characters");
        for (ERole role : ERole.values()) roles.findByName(role).orElseThrow();
        User alice = user("alice.demo", ERole.ROLE_CUSTOMER);
        User bob = user("bob.demo", ERole.ROLE_CUSTOMER);
        user("empty.demo", ERole.ROLE_CUSTOMER);
        user("employee.demo", ERole.ROLE_BANK_EMPLOYEE);
        user("merchant.demo", ERole.ROLE_MERCHANT);
        user("admin.demo", ERole.ROLE_ADMIN);
        account(alice, "9000000001", "1250.00");
        account(bob, "9000000002", "500.00");
    }
    private User user(String username, ERole role) {
        return users.findByUsername(username).orElseGet(() -> users.save(User.builder()
                .username(username).email(username+"@example.test").password(encoder.encode(password))
                .enabled(true).roles(Set.of(roles.findByName(role).orElseThrow())).build()));
    }
    private void account(User user, String number, String amount) {
        if (!accounts.existsByAccountNumber(number)) accounts.save(Account.builder().user(user)
                .accountNumber(number).accountType(AccountType.SAVINGS).currency("USD")
                .balance(new BigDecimal(amount)).status(AccountStatus.ACTIVE).build());
    }
}
