package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.common.exception.*;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.module.auth.dto.*;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.service.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import jakarta.annotation.PostConstruct;
import java.util.*;

@Service @RequiredArgsConstructor
public class AuthServiceImpl implements AuthService {
    private final UserRepository users;
    private final PasswordEncoder passwords;
    private final OtpService otps;
    private final SessionService sessions;
    private final AuthPersistenceService persistence;
    private final LoginAttemptService loginAttempts;
    private String dummyPasswordHash;

    @PostConstruct
    void initializeDummyPassword() {
        dummyPasswordHash = passwords.encode(UUID.randomUUID().toString());
    }

    @Override
    public OtpResponseDto requestOtp(String email, String purpose) {
        email = email.trim().toLowerCase(Locale.ROOT);
        purpose = purpose.toUpperCase(Locale.ROOT);
        // Same response for existing and absent identities; throttle both to resist enumeration.
        boolean deliver = "SIGNUP".equals(purpose) ? !users.existsByEmail(email)
                : users.findByEmail(email).map(User::isEnabled).orElse(false);
        return otps.generateAndSendOtp(email, purpose, deliver);
    }

    @Override
    public TokenResponseDto register(RegisterRequestDto request, String ip) {
        String email = request.getEmail().trim().toLowerCase(Locale.ROOT);
        String username = request.getUsername().trim();
        if (users.existsByUsername(username) || users.existsByEmail(email))
            throw new ApiException(HttpStatus.CONFLICT, "IDENTITY_UNAVAILABLE", "Username or email is unavailable");
        String passwordHash = passwords.encode(request.getPassword());
        otps.validateOtp(email, request.getOtpCode(), "SIGNUP");
        return persistence.register(request, email, passwordHash, ip);
    }

    @Override
    public TokenResponseDto login(LoginRequestDto request, String ip) {
        String identity = request.getUsernameOrEmail().trim();
        User user = users.findByUsername(identity)
                .or(() -> users.findByEmail(identity.toLowerCase(Locale.ROOT))).orElse(null);
        // Case normalization can expand Unicode input beyond the DTO's character limit.
        String key = user == null ? "identity:" + HashUtils.sha256(identity.toLowerCase(Locale.ROOT)) : "user:" + user.getId();
        loginAttempts.recordAttempt(key);
        boolean validPassword = passwords.matches(request.getPassword(),
                user == null || user.getPassword() == null ? dummyPasswordHash : user.getPassword());
        validPassword = validPassword && user != null && user.getPassword() != null;
        if (!validPassword || user == null)
            throw new AuthenticationFailedException("Invalid credentials");
        if (!user.isEnabled()) throw new AuthenticationFailedException("USER_DISABLED", "Account is disabled");
        otps.validateOtp(user.getEmail().trim().toLowerCase(Locale.ROOT), request.getOtpCode(), "LOGIN");
        return persistence.login(user, request, ip);
    }

    @Override
    public TokenResponseDto refreshToken(RefreshTokenRequestDto request) {
        return sessions.refresh(request.getRefreshToken());
    }
}
