package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.module.audit.service.AuditTrail;

import com.bank.digital_banking.common.exception.*;
import com.bank.digital_banking.module.auth.dto.OtpResponseDto;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.*;
import com.bank.digital_banking.module.auth.service.*;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;
import java.security.SecureRandom;
import java.time.*;

@Service @RequiredArgsConstructor
public class OtpServiceImpl implements OtpService {
    private final OtpRepository otps;
    private final OtpRateLimitRepository limits;
    private final EmailService emails;
    private final PasswordEncoder encoder;
    private final AuditTrail audit;
    private final SecureRandom random = new SecureRandom();
    @Value("${app.otp.expiration-minutes:5}") private int expiryMinutes;
    @Value("${app.otp.resend-seconds:60}") private int resendSeconds;
    @Value("${app.otp.max-requests:5}") private int maxRequests;
    @Value("${app.otp.window-minutes:15}") private int windowMinutes;
    @Value("${app.otp.max-attempts:5}") private int maxAttempts;

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public OtpResponseDto generateAndSendOtp(String email, String purpose, boolean deliver) {
        checkPurpose(purpose);
        OtpRateLimit limit = lock(email, purpose);
        OffsetDateTime now = OffsetDateTime.now();
        if (!now.isBefore(limit.getWindowStartedAt().plusMinutes(windowMinutes))) {
            limit.setWindowStartedAt(now);
            limit.setRequestCount(0);
        }
        if (limit.getRequestCount() >= maxRequests)
            throw throttled(limit.getWindowStartedAt().plusMinutes(windowMinutes), now);
        if (limit.getLastRequestedAt() != null && now.isBefore(limit.getLastRequestedAt().plusSeconds(resendSeconds)))
            throw throttled(limit.getLastRequestedAt().plusSeconds(resendSeconds), now);
        limit.setLastRequestedAt(now);
        limit.setRequestCount(limit.getRequestCount() + 1);
        limits.save(limit);
        if (deliver) {
            String raw = String.format(java.util.Locale.ROOT, "%06d", random.nextInt(1_000_000));
            otps.save(OtpVerification.builder().email(email).purpose(purpose).otpCode(encoder.encode(raw))
                    .expiresAt(now.plusMinutes(expiryMinutes)).verified(false).build());
            emails.sendOtpEmail(email, raw, purpose);
        }
        audit.success("AUTH", "OTP_REQUEST_ACCEPTED", null);
        return new OtpResponseDto("If the address is eligible, a verification code has been sent",
                expiryMinutes * 60, resendSeconds);
    }

    // Commit attempts and one-time consumption before the separate session-writing transaction.
    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW, noRollbackFor = ApiException.class)
    public void validateOtp(String email, String input, String purpose) {
        checkPurpose(purpose);
        lock(email, purpose);
        OtpVerification otp = otps.findTopByEmailAndPurposeOrderByIdDesc(email, purpose)
                .orElseThrow(() -> failed("OTP_INVALID", "Request a new verification code"));
        if (otp.isVerified()) throw failed("OTP_USED", "Code was already used; request a new one");
        if (!otp.getExpiresAt().isAfter(OffsetDateTime.now())) throw failed("OTP_EXPIRED", "Code has expired");
        if (otp.getAttempts() >= maxAttempts) throw failed("OTP_ATTEMPTS_EXCEEDED", "Too many attempts; request a new code");
        otp.setAttempts(otp.getAttempts() + 1);
        if (input == null || !encoder.matches(input, otp.getOtpCode())) {
            otps.save(otp);
            throw failed(otp.getAttempts() >= maxAttempts ? "OTP_ATTEMPTS_EXCEEDED" : "OTP_INVALID", "Verification code is invalid");
        }
        otp.setVerified(true);
        otps.save(otp);
    }
    private OtpRateLimit lock(String email, String purpose) {
        String id = email + "|" + purpose;
        limits.ensureExists(id);
        return limits.findLockedById(id).orElseThrow();
    }
    private void checkPurpose(String purpose) {
        if (!"SIGNUP".equals(purpose) && !"LOGIN".equals(purpose))
            throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "Purpose must be SIGNUP or LOGIN");
    }
    private ApiException throttled(OffsetDateTime until, OffsetDateTime now) {
        long seconds = Math.max(1L, (Duration.between(now, until).toMillis() + 999) / 1000);
        return new ApiException(HttpStatus.TOO_MANY_REQUESTS, "OTP_RATE_LIMITED", "Wait before requesting another code", seconds);
    }
    private AuthenticationFailedException failed(String code, String message) {
        return new AuthenticationFailedException(code, message);
    }
}
