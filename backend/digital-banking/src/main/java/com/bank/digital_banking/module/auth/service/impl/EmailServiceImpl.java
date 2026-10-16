package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.service.EmailService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

@Service @RequiredArgsConstructor
public class EmailServiceImpl implements EmailService {
    private final JavaMailSender mail;
    @Value("${spring.mail.username:wallet@example.test}") private String from;
    @Value("${app.otp.expiration-minutes:5}") private int expiry;

    @Override
    public void sendOtpEmail(String email, String otp, String purpose) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(from);
        message.setTo(email);
        message.setSubject("Digital Wallet verification " + purpose);
        message.setText("Your verification code is " + otp + ". It expires in " + expiry + " minutes. Do not share this code.");
        try { mail.send(message); }
        catch (org.springframework.mail.MailException ex) {
            // Never log or return OTPs, credentials, or raw provider exceptions.
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "OTP_DELIVERY_UNAVAILABLE", "Verification email could not be delivered; try again later");
        }
    }
}
