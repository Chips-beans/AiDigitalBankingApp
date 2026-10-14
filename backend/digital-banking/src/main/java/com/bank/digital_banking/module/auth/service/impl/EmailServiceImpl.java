package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.module.auth.service.EmailService;
import jakarta.mail.internet.MimeMessage;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class EmailServiceImpl implements EmailService {

    private final JavaMailSender mailSender;
    private static final Logger log = LoggerFactory.getLogger(EmailServiceImpl.class);

    @Value("${spring.mail.username}")
    private String fromEmail;

    @Async
    @Override
    public void sendOtpEmail(String toEmail, String otpCode, String purpose) {
        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");

            helper.setFrom(fromEmail);
            helper.setTo(toEmail);
            helper.setSubject("Your Digital Wallet OTP Code - " + purpose);

            String htmlContent = """
                <div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px;">
                    <h2 style="color: #1a73e8;">Digital Wallet Verification</h2>
                    <p>Your One-Time Password (OTP) for <strong>%s</strong> is:</p>
                    <div style="font-size: 32px; font-weight: bold; letter-spacing: 5px; color: #d93025; margin: 20px 0;">
                        %s
                    </div>
                    <p>This code will expire in <strong>5 minutes</strong>. Do not share this code with anyone.</p>
                </div>
            """.formatted(purpose, otpCode);

            helper.setText(htmlContent, true);
            mailSender.send(message);
        } catch (Exception e) {
            // Log the OTP code so local testing can proceed without valid SMTP credentials
            log.error("Failed to send SMTP email. LOCAL DEV OTP for {}: [{}]", toEmail, otpCode);
        }
    }
}