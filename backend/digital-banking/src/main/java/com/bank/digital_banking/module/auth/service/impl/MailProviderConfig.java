package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.module.auth.service.EmailService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.event.EventListener;
import org.springframework.mail.javamail.JavaMailSender;
import tools.jackson.databind.ObjectMapper;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Chooses how OTP email is delivered: app.mail.provider (env MAIL_PROVIDER) = smtp (default, local development and
 * tests) or gmail-api (HTTPS, for hosts that block outbound SMTP such as Railway). An unknown value stops startup.
 */
@Configuration
public class MailProviderConfig {
    private static final Logger log = LoggerFactory.getLogger(MailProviderConfig.class);

    @Value("${app.mail.provider:smtp}") private String provider;
    @Value("${spring.mail.username:wallet@example.test}") private String smtpFrom;
    @Value("${app.otp.expiration-minutes:5}") private int expiryMinutes;
    @Value("${app.mail.gmail.client-id:}") private String gmailClientId;
    @Value("${app.mail.gmail.client-secret:}") private String gmailClientSecret;
    @Value("${app.mail.gmail.refresh-token:}") private String gmailRefreshToken;
    @Value("${app.mail.gmail.sender:}") private String gmailSender;
    @Value("${app.mail.gmail.token-url:" + GmailApiEmailService.DEFAULT_TOKEN_URL + "}") private String gmailTokenUrl;
    @Value("${app.mail.gmail.api-url:" + GmailApiEmailService.DEFAULT_API_URL + "}") private String gmailApiUrl;
    @Value("${app.mail.gmail.timeout-ms:5000}") private long gmailTimeoutMs;

    @Bean
    EmailService emailService(ObjectProvider<JavaMailSender> mailSender, ObjectMapper json) {
        return switch (normalized(provider)) {
            case "smtp" -> new EmailServiceImpl(mailSender.getObject(), smtpFrom, expiryMinutes);
            case "gmail-api" -> new GmailApiEmailService(gmailSettings(), json);
            default -> throw new IllegalStateException("app.mail.provider (MAIL_PROVIDER) must be smtp or gmail-api");
        };
    }

    /** Names only, never values: tells an operator which Gmail settings are still missing. */
    @EventListener(ApplicationReadyEvent.class)
    public void reportMailProvider() {
        if (!"gmail-api".equals(normalized(provider))) return;
        List<String> missing = missingGmailSettings(gmailClientId, gmailClientSecret, gmailRefreshToken);
        if (!missing.isEmpty())
            log.warn("MAIL_PROVIDER=gmail-api but {} {} blank: OTP email will fail until set", missing, missing.size() == 1 ? "is" : "are");
        else if (!GmailApiEmailService.secureUrl(gmailTokenUrl) || !GmailApiEmailService.secureUrl(gmailApiUrl))
            log.warn("MAIL_PROVIDER=gmail-api but the Gmail token/API URL is not HTTPS: OTP email will fail");
        else
            log.info("OTP email is delivered through the Gmail API");
    }

    GmailApiEmailService.Settings gmailSettings() {
        return new GmailApiEmailService.Settings(gmailClientId, gmailClientSecret, gmailRefreshToken, gmailSender,
                gmailTokenUrl, gmailApiUrl, Duration.ofMillis(Math.max(500, gmailTimeoutMs)), expiryMinutes);
    }

    static List<String> missingGmailSettings(String clientId, String clientSecret, String refreshToken) {
        List<String> missing = new ArrayList<>();
        if (clientId == null || clientId.isBlank()) missing.add("GMAIL_CLIENT_ID");
        if (clientSecret == null || clientSecret.isBlank()) missing.add("GMAIL_CLIENT_SECRET");
        if (refreshToken == null || refreshToken.isBlank()) missing.add("GMAIL_REFRESH_TOKEN");
        return missing;
    }

    static String normalized(String value) { return value == null ? "smtp" : value.trim().toLowerCase(Locale.ROOT); }
}
