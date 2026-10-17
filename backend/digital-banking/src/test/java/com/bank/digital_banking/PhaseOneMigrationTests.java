package com.bank.digital_banking;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import java.sql.DriverManager;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;

class PhaseOneMigrationTests extends PostgresIntegrationTest {
    @Test void upgradeFromV7PreservesFinancialHistoryAndAddsConstraints() throws Exception {
        String schema = "financial_" + UUID.randomUUID().toString().replace("-", "");
        String url = POSTGRES.getJdbcUrl("postgres", "postgres");
        Flyway.configure().dataSource(url, "postgres", "postgres").schemas(schema).defaultSchema(schema).target("7").load().migrate();
        try (var connection = DriverManager.getConnection(url, "postgres", "postgres"); var sql = connection.createStatement()) {
            sql.execute("set search_path to " + schema);
            sql.execute("insert into users(id,username,email,password_hash) values(1,'upgrade','upgrade@example.test','test-only')");
            sql.execute("insert into accounts(id,user_id,account_number,account_type,currency,balance,status) values(1,1,'8000000001','SAVINGS','USD',100,'ACTIVE')");
            sql.execute("insert into transactions(reference_number,destination_account_id,amount,fee,currency,transaction_type,status) values('LEGACY-1',1,100,0,'USD','DEPOSIT','SUCCESS')");
            sql.execute("insert into audit_logs(module_name,action,severity,success) values('TEST','LEGACY','INFO',true)");
            Flyway.configure().dataSource(url, "postgres", "postgres").schemas(schema).defaultSchema(schema).load().migrate();
            try (var rows = sql.executeQuery("select balance from accounts where id=1")) {
                rows.next(); assertThat(rows.getBigDecimal(1)).isEqualByComparingTo("100");
            }
            try (var rows = sql.executeQuery("select reference_number, initiated_by_user_id from transactions")) {
                rows.next(); assertThat(rows.getString(1)).isEqualTo("LEGACY-1"); assertThat(rows.getObject(2)).isNull();
            }
            assertThatThrownBy(() -> sql.execute("update accounts set balance=-1 where id=1")).isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> sql.execute("update transactions set amount=0")).isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> sql.execute("update transactions set fee=-1")).isInstanceOf(java.sql.SQLException.class);
            try (var rows = sql.executeQuery("select count(*) from audit_logs where action='LEGACY'")) {
                rows.next(); assertThat(rows.getInt(1)).isEqualTo(1);
            }
        }
    }

    @Test void invalidLegacyMoneyStopsTheMigrationWithoutSilentlyChangingIt() throws Exception {
        String schema = "invalid_" + UUID.randomUUID().toString().replace("-", "");
        String url = POSTGRES.getJdbcUrl("postgres", "postgres");
        Flyway.configure().dataSource(url, "postgres", "postgres").schemas(schema).defaultSchema(schema).target("7").load().migrate();
        try (var connection = DriverManager.getConnection(url, "postgres", "postgres"); var sql = connection.createStatement()) {
            sql.execute("set search_path to " + schema);
            sql.execute("insert into users(id,username,email,password_hash) values(1,'badlegacy','badlegacy@example.test','test-only')");
            sql.execute("insert into accounts(id,user_id,account_number,account_type,currency,balance,status) values(1,1,'8000000002','SAVINGS','USD',-5,'ACTIVE')");
            assertThatThrownBy(() -> Flyway.configure().dataSource(url, "postgres", "postgres").schemas(schema).defaultSchema(schema).load().migrate())
                    .hasStackTraceContaining("Financial preflight failed");
            try (var rows = sql.executeQuery("select balance from accounts where id=1")) {
                rows.next(); assertThat(rows.getBigDecimal(1)).isEqualByComparingTo("-5");
            }
            try (var rows = sql.executeQuery("select count(*) from information_schema.tables where table_schema='"+schema+"' and table_name='idempotency_records'")) {
                rows.next(); assertThat(rows.getInt(1)).isZero();
            }
        }
    }
}
