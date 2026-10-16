package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.common.exception.*;
import com.bank.digital_banking.module.auth.dto.*;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.service.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service @RequiredArgsConstructor
public class AuthServiceImpl implements AuthService {
    private final UserRepository users;
    private final RoleRepository roles;
    private final PasswordEncoder passwords;
    private final OtpService otps;
    private final DeviceService devices;
    private final SessionService sessions;

    @Override
    public OtpResponseDto requestOtp(String email, String purpose) {
        email = email.trim().toLowerCase(Locale.ROOT);
        purpose = purpose.toUpperCase(Locale.ROOT);
        // Same response for existing and absent identities; throttle both to resist enumeration.
        boolean deliver = "SIGNUP".equals(purpose) ? !users.existsByEmail(email)
                : users.findByEmail(email).map(User::isEnabled).orElse(false);
        return otps.generateAndSendOtp(email, purpose, deliver);
    }

    @Override @Transactional
    public TokenResponseDto register(RegisterRequestDto request, String ip) {
        String email = request.getEmail().trim().toLowerCase(Locale.ROOT);
        String username = request.getUsername().trim();
        if (users.existsByUsername(username) || users.existsByEmail(email))
            throw new ApiException(HttpStatus.CONFLICT, "IDENTITY_UNAVAILABLE", "Username or email is unavailable");
        otps.validateOtp(email, request.getOtpCode(), "SIGNUP");
        Role role = roles.findByName(ERole.ROLE_CUSTOMER).orElseThrow(() -> new IllegalStateException("Customer role missing"));
        User user = users.save(User.builder().username(username).email(email).password(passwords.encode(request.getPassword()))
                .firstName(request.getFirstName()).lastName(request.getLastName()).enabled(true).roles(Set.of(role)).build());
        Device device = devices.bind(user, request.getDeviceFingerprint(), request.getDeviceName(), request.getDeviceType(), null, ip);
        return sessions.create(user, device);
    }

    @Override @Transactional
    public TokenResponseDto login(LoginRequestDto request, String ip) {
        String identity = request.getUsernameOrEmail().trim();
        User candidate = users.findByUsername(identity).orElseGet(() ->
                users.findByEmail(identity.toLowerCase(Locale.ROOT)).orElseThrow(() -> new AuthenticationFailedException("Invalid credentials")));
        User user = users.findLockedById(candidate.getId()).orElseThrow();
        if (!passwords.matches(request.getPassword(), user.getPassword()))
            throw new AuthenticationFailedException("Invalid credentials");
        if (!user.isEnabled()) throw new AuthenticationFailedException("USER_DISABLED", "Account is disabled");
        otps.validateOtp(user.getEmail(), request.getOtpCode(), "LOGIN");
        Device device = devices.bind(user, request.getDeviceFingerprint(), request.getDeviceName(), request.getDeviceType(), null, ip);
        return sessions.create(user, device);
    }

    @Override
    public TokenResponseDto refreshToken(RefreshTokenRequestDto request) {
        return sessions.refresh(request.getRefreshToken());
    }
}
