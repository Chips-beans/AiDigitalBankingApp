package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import com.bank.digital_banking.module.auth.entity.OtpVerification;
import com.bank.digital_banking.module.auth.repository.OtpRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.OffsetDateTime;

@Service
@RequiredArgsConstructor
public class OtpService {

    private final OtpRepository otpRepository;
    private final EmailService emailService;
    private final SecureRandom secureRandom = new SecureRandom();

    @Value("${app.otp.expiration-minutes:5}")
    private int otpExpirationMinutes;

    /**
     * Generates a 6-digit OTP, persists it, and sends it to the user's Gmail.
     */
    @Transactional
    public void generateAndSendOtp(String email, String purpose) {
        String otpCode = String.format("%06d", secureRandom.nextInt(1000000));

        OtpVerification otpVerification = OtpVerification.builder()
                .email(email)
                .otpCode(otpCode)
                .purpose(purpose)
                .verified(false)
                .expiresAt(OffsetDateTime.now().plusMinutes(otpExpirationMinutes))
                .build();

        otpRepository.save(otpVerification);
        emailService.sendOtpEmail(email, otpCode, purpose);
    }

    /**
     * Validates the provided OTP code against stored records.
     */
    @Transactional
    public void validateOtp(String email, String inputCode, String purpose) {
        OtpVerification otp = otpRepository
                .findTopByEmailAndPurposeAndVerifiedFalseOrderByCreatedAtDesc(email, purpose)
                .orElseThrow(() -> new AuthenticationFailedException("No active OTP request found for " + email));

        if (otp.getExpiresAt().isBefore(OffsetDateTime.now())) {
            throw new AuthenticationFailedException("OTP code has expired. Please request a new one.");
        }

        if (!otp.getOtpCode().equals(inputCode)) {
            throw new AuthenticationFailedException("Invalid OTP code");
        }

        otp.setVerified(true);
        otpRepository.save(otp);
    }
}
