package com.bank.digital_banking;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest(classes = DigitalBankingApplication.class, webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles({"local", "test"})
// Legacy suites post transfers directly; TransferPinAndExchangeTests overrides this to true.
@org.springframework.test.context.TestPropertySource(properties = "app.transfer.pin-proof-required=false")
abstract class PostgresIntegrationTest {
    static final String PASSWORD = "LocalTestOnly!2026";
    static final String SECRET = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=";
    static final EmbeddedPostgres POSTGRES;
    static final LocalSmtpServer SMTP;
    static {
        try {
            POSTGRES = EmbeddedPostgres.builder().setPort(0).start();
            SMTP = new LocalSmtpServer();
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                try { SMTP.close(); POSTGRES.close(); } catch (Exception ignored) { }
            }));
        } catch (Exception ex) { throw new ExceptionInInitializerError(ex); }
    }
    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", () -> POSTGRES.getJdbcUrl("postgres", "postgres"));
        r.add("spring.datasource.username", () -> "postgres");
        r.add("spring.datasource.password", () -> "postgres");
        r.add("spring.datasource.hikari.maximum-pool-size", () -> 2);
        r.add("spring.datasource.hikari.minimum-idle", () -> 0);
        r.add("spring.datasource.hikari.connection-timeout", () -> 1500);
        r.add("app.jwt.secret", () -> SECRET);
        r.add("app.dev.seed.enabled", () -> true);
        r.add("app.dev.seed.password", () -> PASSWORD);
        // Always capture test mail locally, regardless of inherited Gmail provider configuration.
        r.add("app.mail.provider", () -> "smtp");
        r.add("spring.mail.host", () -> "localhost");
        r.add("spring.mail.port", SMTP::port);
        r.add("spring.mail.properties.mail.smtp.auth", () -> false);
        r.add("spring.mail.properties.mail.smtp.starttls.enable", () -> false);
        r.add("spring.mail.properties.mail.smtp.starttls.required", () -> false);
        r.add("app.ai.enabled", () -> false);
        r.add("app.ai.gateway.enabled", () -> false);
        r.add("app.ai.gateway.customer-context-enabled", () -> false);
        r.add("spring.main.banner-mode", () -> "off");
        r.add("logging.level.root", () -> "WARN");
        r.add("logging.level.org.springframework.boot.autoconfigure", () -> "ERROR");
    }
}
