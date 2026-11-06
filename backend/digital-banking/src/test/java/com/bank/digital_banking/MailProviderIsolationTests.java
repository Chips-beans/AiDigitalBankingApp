package com.bank.digital_banking;

import com.bank.digital_banking.module.auth.service.EmailService;
import com.bank.digital_banking.module.auth.service.impl.EmailServiceImpl;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.Environment;

import java.util.UUID;

import static org.assertj.core.api.Assertions.*;

@SpringBootTest(classes = DigitalBankingApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "app.mail.provider=gmail-api")
class MailProviderIsolationTests extends PostgresIntegrationTest {
    @Autowired EmailService email;
    @Autowired Environment environment;

    @Test void sharedFixtureOverridesGmailAndDeliversOnlyToLocalSmtp() {
        // Assert before delivery: even the unfixed baseline must never call Gmail.
        assertThat(email).isInstanceOf(EmailServiceImpl.class);
        assertThat(environment.getProperty("app.mail.provider")).isEqualTo("smtp");
        String recipient = "mail-isolation-" + UUID.randomUUID() + "@example.test";
        email.sendOtpEmail(recipient, "482159", "LOGIN");
        assertThatCode(() -> SMTP.code(recipient)).doesNotThrowAnyException();
    }
}
