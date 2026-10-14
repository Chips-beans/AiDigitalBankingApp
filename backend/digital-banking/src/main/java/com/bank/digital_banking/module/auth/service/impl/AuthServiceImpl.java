package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.module.auth.dto.*;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.DeviceRepository;
import com.bank.digital_banking.module.auth.repository.RoleRepository;
import com.bank.digital_banking.module.auth.repository.UserRepository;
import com.bank.digital_banking.module.auth.security.JwtTokenProvider;
import com.bank.digital_banking.module.auth.service.AuthService;
import com.bank.digital_banking.module.auth.service.OtpService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class AuthServiceImpl implements AuthService {

    private final UserRepository userRepository;
    private final RoleRepository roleRepository;
    private final DeviceRepository deviceRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;
    private final OtpService otpService;

    @Value("${app.jwt.expiration-ms:86400000}")
    private long jwtExpirationMs;

    // =========================================================================
    // 1. REQUEST OTP ENDPOINT
    // =========================================================================

    @Override
    public void requestOtp(String email, String purpose) {
        if ("SIGNUP".equalsIgnoreCase(purpose) && userRepository.existsByEmail(email)) {
            throw new IllegalArgumentException("Email is already registered");
        }
        if ("LOGIN".equalsIgnoreCase(purpose) && !userRepository.existsByEmail(email)) {
            throw new ResourceNotFoundException("No account associated with this email");
        }
        otpService.generateAndSendOtp(email, purpose);
    }

    /**
     * Registers a new user account with default CUSTOMER role and registers the initiating device.
     */
    @Override
    @Transactional
    public TokenResponseDto register(RegisterRequestDto request, String clientIp) {
        // STAGE 1: OTP VALIDATION STAGE
        otpService.validateOtp(request.getEmail(), request.getOtpCode(), "SIGNUP");

        // STAGE 2: UNIQUE CREDENTIALS CHECK
        if (userRepository.existsByUsername(request.getUsername())) {
            throw new IllegalArgumentException("Username is already taken");
        }

        // STAGE 3: ROLE ASSIGNMENT & USER PERSISTENCE
        Role customerRole = roleRepository.findByName(ERole.ROLE_CUSTOMER)
                .orElseThrow(() -> new ResourceNotFoundException("Default ROLE_CUSTOMER not found"));

        User user = User.builder()
                .username(request.getUsername())
                .email(request.getEmail())
                .password(passwordEncoder.encode(request.getPassword()))
                .firstName(request.getFirstName())
                .lastName(request.getLastName())
                .enabled(true)
                .roles(Set.of(customerRole))
                .build();

        User savedUser = userRepository.save(user);

        // STAGE 4: DEVICE BINDING
        if (request.getDeviceFingerprint() != null && !request.getDeviceFingerprint().isBlank()) {
            registerOrUpdateDevice(savedUser, request.getDeviceFingerprint(), request.getDeviceName(), request.getDeviceType(), clientIp);
        }

        // STAGE 5: TOKEN ISSUANCE
        return generateTokenResponse(savedUser);
    }

    /**
     * Authenticates user credentials and verifies/binds the logging-in device.
     */
    @Override
    @Transactional
    public TokenResponseDto login(LoginRequestDto request, String clientIp) {
        // STAGE 1: USER LOOKUP & PASSWORD CHECK
        User user = userRepository.findByUsername(request.getUsernameOrEmail())
                .orElseGet(() -> userRepository.findByEmail(request.getUsernameOrEmail())
                        .orElseThrow(() -> new AuthenticationFailedException("Invalid credentials")));

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new AuthenticationFailedException("Invalid credentials");
        }

        // STAGE 2: OTP 2FA VALIDATION
        otpService.validateOtp(user.getEmail(), request.getOtpCode(), "LOGIN");

        // STAGE 3: DEVICE BINDING & TOKEN ISSUANCE
        registerOrUpdateDevice(user, request.getDeviceFingerprint(), request.getDeviceName(), request.getDeviceType(), clientIp);
        return generateTokenResponse(user);
    }

    /**
     * Validates a refresh token and generates a fresh token pair.
     */
    @Override
    @Transactional(readOnly = true)
    public TokenResponseDto refreshToken(RefreshTokenRequestDto request) {
        String token = request.getRefreshToken();

        // STAGE 1: TOKEN VALIDATION STAGE
        if (!tokenProvider.validateToken(token)) {
            throw new AuthenticationFailedException("Invalid or expired refresh token");
        }

        // STAGE 2: USER RETRIEVAL STAGE
        String username = tokenProvider.getUsernameFromToken(token);
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("User not found for token"));

        // STAGE 3: STATUS VERIFICATION STAGE
        if (!user.isEnabled()) {
            throw new AuthenticationFailedException("Account is disabled");
        }

        // STAGE 4: TOKEN RE-ISSUANCE STAGE
        return generateTokenResponse(user);
    }

    /**
     * Internal helper to register a new device or update the last login timestamp of an existing one.
     */
    private void registerOrUpdateDevice(User user, String fingerprint, String name, String type, String ipAddress) {

        // STAGE 1: DEVICE LOOKUP & CREATION STAGE
        Device device = deviceRepository.findByDeviceFingerprint(fingerprint)
                .orElseGet(() -> Device.builder()
                        .user(user)
                        .deviceFingerprint(fingerprint)
                        .deviceName(name != null ? name : "Unknown Device")
                        .deviceType(type != null ? type : "MOBILE")
                        .status(DeviceStatus.ACTIVE)
                        .build());

        // STAGE 2: SECURITY & REVOCATION CHECKS STAGE
        if (device.getId() != null && !device.getUser().getId().equals(user.getId())) {
            throw new AuthenticationFailedException("Device fingerprint is associated with another account");
        }

        if (device.getStatus() == DeviceStatus.REVOKED) {
            throw new AuthenticationFailedException("This device has been revoked. Access denied.");
        }

        // STAGE 3: AUDIT UPDATE & SAVE STAGE
        device.setIpAddress(ipAddress);
        device.setLastLoginAt(OffsetDateTime.now());
        deviceRepository.save(device);
    }

    /**
     * Constructs the standard TokenResponseDto envelope containing JWT tokens and role claims.
     */
    private TokenResponseDto generateTokenResponse(User user) {

        // STAGE 1: CLAIMS EXTRACTION STAGE
        Set<String> roleNames = user.getRoles().stream()
                .map(role -> role.getName().name())
                .collect(Collectors.toSet());

        // STAGE 2: JWT SIGNING STAGE
        String accessToken = tokenProvider.generateAccessToken(user.getUsername(), roleNames);
        String refreshToken = tokenProvider.generateRefreshToken(user.getUsername());

        // STAGE 3: RESPONSE DTO BUILDING STAGE
        return TokenResponseDto.builder()
                .accessToken(accessToken)
                .refreshToken(refreshToken)
                .tokenType("Bearer")
                .expiresInMs(jwtExpirationMs)
                .username(user.getUsername())
                .roles(roleNames)
                .build();
    }
}