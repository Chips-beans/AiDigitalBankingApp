package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import com.bank.digital_banking.module.auth.dto.*;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.Set;

/** Atomic identity/device/session writes after password and OTP verification have finished. */
@Service
@RequiredArgsConstructor
public class AuthPersistenceService {
    private final UserRepository users;
    private final RoleRepository roles;
    private final DeviceService devices;
    private final SessionService sessions;

    @Transactional
    public TokenResponseDto register(RegisterRequestDto request, String email, String passwordHash, String ip) {
        Role role = roles.findByName(ERole.ROLE_CUSTOMER)
                .orElseThrow(() -> new IllegalStateException("Customer role missing"));
        User user = users.save(User.builder().username(request.getUsername().trim()).email(email)
                .password(passwordHash).firstName(request.getFirstName()).lastName(request.getLastName())
                .enabled(true).roles(Set.of(role)).build());
        Device device = devices.bind(user, request.getDeviceFingerprint(), request.getDeviceName(),
                request.getDeviceType(), null, ip);
        return sessions.create(user, device);
    }

    @Transactional
    public TokenResponseDto login(User verifiedUser, LoginRequestDto request, String ip) {
        // Serialize session replacement; load fresh state after acquiring the user lock.
        User user = users.findLockedById(verifiedUser.getId())
                .orElseThrow(() -> new AuthenticationFailedException("Invalid credentials"));
        if (!user.isEnabled()) throw new AuthenticationFailedException("USER_DISABLED", "Account is disabled");
        if (!user.getPassword().equals(verifiedUser.getPassword())) {
            throw new AuthenticationFailedException("Credentials changed; sign in again");
        }
        Device device = devices.bind(user, request.getDeviceFingerprint(), request.getDeviceName(),
                request.getDeviceType(), null, ip);
        return sessions.create(user, device);
    }
}
