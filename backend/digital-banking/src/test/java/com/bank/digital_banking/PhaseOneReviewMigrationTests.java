package com.bank.digital_banking;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import java.sql.DriverManager;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;

class PhaseOneReviewMigrationTests extends PostgresIntegrationTest {
    @Test void v8UpgradePreservesBalancesHistoryAndIdempotencyResults() throws Exception {
        String schema=schema(); String url=POSTGRES.getJdbcUrl("postgres","postgres");
        baseline(schema);
        try(var connection=DriverManager.getConnection(url,"postgres","postgres"); var sql=connection.createStatement()) {
            sql.execute("set search_path to "+schema);
            seed(sql);
            sql.execute("insert into idempotency_records(actor_user_id,operation,request_key,request_hash,transaction_id,response_json) values(1,'DEPOSIT','existing-key',repeat('a',64),1,'{\"referenceNumber\":\"QA-V8\"}')");
            latest(schema);
            try(var rows=sql.executeQuery("select a.balance,t.reference_number,i.response_json from accounts a join transactions t on t.destination_account_id=a.id join idempotency_records i on i.transaction_id=t.id")) {
                rows.next(); assertThat(rows.getBigDecimal(1)).isEqualByComparingTo("100");
                assertThat(rows.getString(2)).isEqualTo("QA-V8");
                assertThat(rows.getString(3)).isEqualTo("{\"referenceNumber\":\"QA-V8\"}");
            }
            assertThatThrownBy(() -> sql.execute("update accounts set balance='NaN'::numeric where id=1")).isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> sql.execute("update transactions set amount='NaN'::numeric where id=1")).isInstanceOf(java.sql.SQLException.class);
            assertThatThrownBy(() -> sql.execute("update transactions set fee='NaN'::numeric where id=1")).isInstanceOf(java.sql.SQLException.class);
        }
    }

    @ParameterizedTest
    @ValueSource(strings={"balance","amount","fee"})
    void v9RefusesLegacyNotANumberWithoutChangingFinancialRecords(String column) throws Exception {
        String schema=schema(); String url=POSTGRES.getJdbcUrl("postgres","postgres");
        baseline(schema);
        try(var connection=DriverManager.getConnection(url,"postgres","postgres"); var sql=connection.createStatement()) {
            sql.execute("set search_path to "+schema);
            seed(sql);
            String table=column.equals("balance")?"accounts":"transactions";
            sql.execute("update "+table+" set "+column+"='NaN'::numeric where id=1");
            assertThatThrownBy(() -> latest(schema)).hasStackTraceContaining("non-finite money");
            try(var rows=sql.executeQuery("select "+column+"::text from "+table+" where id=1")) {
                rows.next(); assertThat(rows.getString(1)).isEqualTo("NaN");
            }
            try(var rows=sql.executeQuery("select count(*) from pg_constraint where connamespace='"+schema+"'::regnamespace and conname in ('ck_accounts_finite_money','ck_transactions_finite_money')")) {
                rows.next(); assertThat(rows.getInt(1)).isZero();
            }
        }
    }

    void baseline(String schema) { Flyway.configure().dataSource(POSTGRES.getJdbcUrl("postgres","postgres"),"postgres","postgres").schemas(schema).defaultSchema(schema).target("8").load().migrate(); }
    void latest(String schema) { Flyway.configure().dataSource(POSTGRES.getJdbcUrl("postgres","postgres"),"postgres","postgres").schemas(schema).defaultSchema(schema).load().migrate(); }
    String schema() { return "qa_"+UUID.randomUUID().toString().replace("-",""); }
    void seed(java.sql.Statement sql) throws Exception {
        sql.execute("insert into users(id,username,email,password_hash) values(1,'qa','qa@example.test','test-only')");
        sql.execute("insert into accounts(id,user_id,account_number,account_type,currency,balance,status) values(1,1,'8000000003','SAVINGS','USD',100,'ACTIVE')");
        sql.execute("insert into transactions(id,reference_number,destination_account_id,amount,fee,currency,transaction_type,status) values(1,'QA-V8',1,100,0,'USD','DEPOSIT','SUCCESS')");
    }
}
