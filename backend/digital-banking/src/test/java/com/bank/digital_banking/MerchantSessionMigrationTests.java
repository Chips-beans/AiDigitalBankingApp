package com.bank.digital_banking;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import java.util.UUID;
import static org.assertj.core.api.Assertions.*;

class MerchantSessionMigrationTests {
    @Test void v18BackfillsExistingV17SessionWithoutChangingCredentialsOrRevocation() throws Exception {
        try(var pg=EmbeddedPostgres.builder().setPort(0).start()) {
            String url=pg.getJdbcUrl("postgres","postgres");
            Flyway.configure().dataSource(url,"postgres","postgres").target("17").load().migrate();
            UUID active=UUID.randomUUID(),revoked=UUID.randomUUID();
            try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()) {
                s.executeUpdate("INSERT INTO users(username) VALUES ('m2.upgrade')");
                s.executeUpdate("INSERT INTO devices(user_id,device_name,device_fingerprint) SELECT id,'Existing Customer','upgrade-device' FROM users WHERE username='m2.upgrade'");
                for(var id:new UUID[]{active,revoked}) s.executeUpdate("INSERT INTO auth_sessions(id,user_id,device_id,refresh_token_hash,created_at,expires_at,revoked_at) "
                        +"SELECT '"+id+"',user_id,id,repeat('a',64),CURRENT_TIMESTAMP-INTERVAL '1 day',CURRENT_TIMESTAMP+INTERVAL '1 day',"
                        +(id.equals(revoked)?"CURRENT_TIMESTAMP":"NULL")+" FROM devices WHERE device_fingerprint='upgrade-device'");
            }
            var upgrade=Flyway.configure().dataSource(url,"postgres","postgres").load(); upgrade.migrate(); upgrade.validate();
            try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement();var r=s.executeQuery("SELECT id,purpose,client_id,refresh_token_hash,revoked_at FROM auth_sessions ORDER BY id")) {
                int count=0; while(r.next()) {
                    assertThat(r.getString("purpose")).isEqualTo("CUSTOMER");
                    assertThat(r.getString("client_id")).isEqualTo("kesor-customer");
                    assertThat(r.getString("refresh_token_hash")).isEqualTo("a".repeat(64));
                    assertThat(r.getObject("revoked_at")!=null).isEqualTo(revoked.equals(r.getObject("id",UUID.class))); count++;
                } assertThat(count).isEqualTo(2);
            }
        }
    }

    @Test void v19PreservesLegacyShopsAndHaltsOnDuplicateMerchantWallets() throws Exception {
        for (boolean duplicate : new boolean[]{false, true}) {
            try(var pg=EmbeddedPostgres.builder().setPort(0).start()) {
                String url=pg.getJdbcUrl("postgres","postgres");
                Flyway.configure().dataSource(url,"postgres","postgres").target("18").load().migrate();
                try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement()) {
                    s.executeUpdate("INSERT INTO users(username) VALUES ('m4.upgrade')");
                    for (int i=0;i<2;i++) s.executeUpdate("INSERT INTO merchants(merchant_id,store_name,bakong_account_id,merchant_city,status,owner_user_id) "
                            +"SELECT 'LEGACY-"+i+"','Legacy "+i+"','legacy"+i+"@bank','Phnom Penh','ACTIVE',id FROM users WHERE username='m4.upgrade'");
                    for (String number : duplicate ? new String[]{"9000000001","9000000002"} : new String[]{"9000000001"})
                        s.executeUpdate("INSERT INTO accounts(user_id,account_number,account_type,currency,balance,status,account_category,merchant_id) "
                                +"SELECT u.id,'"+number+"','CHECKING','USD',12.50,'ACTIVE','MERCHANT',m.id FROM users u JOIN merchants m ON m.owner_user_id=u.id "
                                +"WHERE u.username='m4.upgrade' AND m.merchant_id='LEGACY-0'");
                }
                var upgrade=Flyway.configure().dataSource(url,"postgres","postgres").load();
                if (duplicate) {
                    assertThatThrownBy(upgrade::migrate).hasMessageContaining("V19 preflight");
                    continue;
                }
                upgrade.migrate(); upgrade.validate();
                try(var c=pg.getPostgresDatabase().getConnection();var s=c.createStatement();
                    var r=s.executeQuery("SELECT onboarding,profile_version,(SELECT sum(balance) FROM accounts) FROM merchants ORDER BY id")) {
                    int count=0; while(r.next()) {
                        assertThat(r.getString(1)).isEqualTo("LEGACY"); assertThat(r.getLong(2)).isZero();
                        assertThat(r.getBigDecimal(3)).isEqualByComparingTo("12.50"); count++;
                    } assertThat(count).isEqualTo(2);
                }
            }
        }
    }
}
