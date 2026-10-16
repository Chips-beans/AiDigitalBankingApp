package com.bank.digital_banking;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import java.sql.DriverManager;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;

class PhaseZeroMigrationTests extends PostgresIntegrationTest {
    @Test void versionSevenPreservesExistingUsersSessionsAndOtpsAndAddsConstraints() throws Exception {
        String schema = "review_" + UUID.randomUUID().toString().replace("-", "");
        String url = POSTGRES.getJdbcUrl("postgres", "postgres");
        Flyway.configure().dataSource(url, "postgres", "postgres").schemas(schema).defaultSchema(schema)
                .target("6").load().migrate();
        try (var connection = DriverManager.getConnection(url, "postgres", "postgres");
             var statement = connection.createStatement()) {
            // schema consists only of the fixed prefix and generated hexadecimal UUID.
            statement.execute("set search_path to " + schema);
            statement.execute("insert into users(id, username, email, password_hash) values (1, 'review', 'REVIEW@EXAMPLE.TEST', 'test-only')");
            statement.execute("insert into devices(id, user_id, device_name, device_fingerprint) values (1, 1, 'Test', 'test-device')");
            String session = UUID.randomUUID().toString();
            String insertSession = "insert into auth_sessions(id, user_id, device_id, refresh_token_hash, created_at, expires_at) "
                    + "values ('%s', 1, 1, repeat('a',64), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + interval '7 days')";
            statement.execute(insertSession.formatted(session));
            statement.execute("insert into otp_verifications(email, otp_code, purpose, expires_at) "
                    + "values ('review@example.test', 'test-only-hash', 'LOGIN', CURRENT_TIMESTAMP + interval '5 minutes')");
            Flyway.configure().dataSource(url, "postgres", "postgres").schemas(schema).defaultSchema(schema).load().migrate();
            try (var rows = statement.executeQuery("select (select count(*) from users) as users, "
                    + "(select count(*) from auth_sessions) as sessions, (select count(*) from otp_verifications) as otps")) {
                assertThat(rows.next()).isTrue();
                assertThat(rows.getLong("users")).isEqualTo(1);
                assertThat(rows.getLong("sessions")).isEqualTo(1);
                assertThat(rows.getLong("otps")).isEqualTo(1);
            }
            assertThatThrownBy(() -> statement.execute(insertSession.formatted(UUID.randomUUID())))
                    .isInstanceOf(java.sql.SQLException.class)
                    .satisfies(ex -> assertThat(((java.sql.SQLException) ex).getSQLState()).isEqualTo("23505"));
            assertThatThrownBy(() -> statement.execute("insert into users(id, username, email, password_hash) "
                    + "values (2, 'duplicate', 'review@example.test', 'test-only')"))
                    .isInstanceOf(java.sql.SQLException.class)
                    .satisfies(ex -> assertThat(((java.sql.SQLException) ex).getSQLState()).isEqualTo("23505"));
            statement.execute("update auth_sessions set revoked_at = CURRENT_TIMESTAMP");
            statement.execute(insertSession.formatted(UUID.randomUUID()));
            try (var rows = statement.executeQuery("select indexname from pg_indexes where schemaname = '" + schema + "'")) {
                var indexes = new java.util.HashSet<String>();
                while (rows.next()) indexes.add(rows.getString(1));
                assertThat(indexes).contains("idx_accounts_user", "idx_otp_email_purpose_id", "uq_sessions_current_device", "uq_users_email_normalized")
                        .doesNotContain("idx_otp_email_purpose_created");
            }
        }
        // The isolated embedded PostgreSQL instance removes this test schema on shutdown.
    }
}
