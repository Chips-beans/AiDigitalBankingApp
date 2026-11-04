package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.service.EmailService;
import org.springframework.http.HttpStatus;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;

/** SMTP delivery (app.mail.provider=smtp, the default). Created by {@link MailProviderConfig}. */
public class EmailServiceImpl implements EmailService {
    private final JavaMailSender mail;
    private final String from;
    private final int expiry;

    public EmailServiceImpl(JavaMailSender mail, String from, int expiry) {
        this.mail = mail;
        this.from = from;
        this.expiry = expiry;
    }

    @Override
    public void sendOtpEmail(String email, String otp, String purpose) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(from);
        message.setTo(email);
        message.setSubject(OtpEmailText.subject(purpose));
        message.setText(OtpEmailText.body(otp, expiry));
        try { mail.send(message); }
        catch (org.springframework.mail.MailException ex) {
            // Never log or return OTPs, credentials, or raw provider exceptions.
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "OTP_DELIVERY_UNAVAILABLE", "Verification email could not be delivered; try again later");
        }
    }
}
