package com.bank.digital_banking.module.auth.merchant;

import com.bank.digital_banking.common.exception.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class MerchantAuthConfigTests {
    static final String JWT="MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=";
    MockEnvironment environment(String... profiles) {
        var e=new MockEnvironment().withProperty("app.jwt.secret",JWT); e.setActiveProfiles(profiles); return e;
    }
    @Test void developmentDefaultsAreExactAndProductionIsDisabled() {
        var dev=new MerchantAuthConfig(environment("local","test"));
        assertThat(dev.enabled).isTrue(); assertThat(dev.callback).isEqualTo("kesormerchant://auth/callback");
        for(String[] profiles:List.of(new String[]{"prod"},new String[]{"dev","prod"},new String[]{"production"},new String[]{})) {
            var prod=new MerchantAuthConfig(environment(profiles)); assertThat(prod.enabled).isFalse();
            assertThatThrownBy(prod::requireEnabled).isInstanceOf(ApiException.class);
        }
    }
    @Test void productionRequiresHttpsLinksAndIndependentEncryptionKey() {
        var e=environment("prod").withProperty("app.merchant-auth.enabled","true");
        assertThatThrownBy(()->new MerchantAuthConfig(e)).isInstanceOf(IllegalArgumentException.class);
        e.withProperty("app.merchant-auth.callback-uri","https://bank.example/merchant/callback")
                .withProperty("app.merchant-auth.approval-uri","https://bank.example/customer/merchant-approval")
                .withProperty("app.merchant-auth.recovery-key",JWT);
        assertThatThrownBy(()->new MerchantAuthConfig(e)).isInstanceOf(IllegalArgumentException.class);
        byte[] independent=new byte[32]; Arrays.fill(independent,(byte)87);
        e.withProperty("app.merchant-auth.recovery-key",Base64.getEncoder().encodeToString(independent));
        assertThat(new MerchantAuthConfig(e).enabled).isTrue();
        for(String bad:List.of("kesormerchant://auth/callback","http://bank.example/callback","https://bank.example/callback?x=1",
                "https://user@bank.example/callback","https://bank.example/callback#fragment")) {
            e.withProperty("app.merchant-auth.callback-uri",bad);
            assertThatThrownBy(()->new MerchantAuthConfig(e)).as(bad).isInstanceOf(IllegalArgumentException.class);
        }
    }
    @Test void recoveryEncryptionSurvivesRecreationButRejectsTamperingWrongAttemptAndKey() {
        var one=new MerchantAuthConfig(environment("test")); UUID id=UUID.randomUUID();
        String receipt=MerchantAuthCrypto.seal(one.recoveryKey,id,"synthetic private response");
        var recreated=new MerchantAuthConfig(environment("test"));
        assertThat(MerchantAuthCrypto.open(recreated.recoveryKey,id,receipt)).isEqualTo("synthetic private response");
        assertThat(receipt).doesNotContain("synthetic");
        assertThatThrownBy(()->MerchantAuthCrypto.open(one.recoveryKey,UUID.randomUUID(),receipt)).isInstanceOf(IllegalStateException.class);
        byte[] bytes=Base64.getDecoder().decode(receipt); bytes[bytes.length-1]^=1;
        assertThatThrownBy(()->MerchantAuthCrypto.open(one.recoveryKey,id,Base64.getEncoder().encodeToString(bytes))).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(()->MerchantAuthCrypto.open(Base64.getEncoder().encodeToString(new byte[32]),id,receipt)).isInstanceOf(IllegalStateException.class);
    }
}
