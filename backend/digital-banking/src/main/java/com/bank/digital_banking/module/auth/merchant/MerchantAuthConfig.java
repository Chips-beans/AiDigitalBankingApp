package com.bank.digital_banking.module.auth.merchant;

import com.bank.digital_banking.common.exception.ApiException;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import java.net.URI;
import java.util.*;

/** One registered public client. No client secret is shipped in either app. */
@Component
public class MerchantAuthConfig {
    public static final String CLIENT = "kesor-merchant-android";
    public static final String PACKAGE = "com.bank.merchant_app";
    public static final String NAME = "Kesor Merchant";
    public final boolean enabled;
    public final String callback;
    public final String approval;
    public final String recoveryKey;
    /** Owner transfers (M8) use their own exact links; blank outside development disables them only. */
    public final boolean transfersEnabled;
    public final String transferApproval;
    public final String transferCallback;

    public MerchantAuthConfig(Environment env) {
        var profiles = Set.of(env.getActiveProfiles());
        boolean development = !profiles.contains("prod") && !profiles.contains("production")
                && profiles.stream().anyMatch(Set.of("local", "dev", "test")::contains);
        enabled = env.getProperty("app.merchant-auth.enabled", Boolean.class,
                env.getProperty("MERCHANT_AUTH_ENABLED", Boolean.class, development));
        callback = env.getProperty("app.merchant-auth.callback-uri",
                env.getProperty("MERCHANT_AUTH_CALLBACK_URI", development ? "kesormerchant://auth/callback" : ""));
        approval = env.getProperty("app.merchant-auth.approval-uri",
                env.getProperty("MERCHANT_AUTH_APPROVAL_URI", development ? "kesorbank://merchant/approve" : ""));
        transferApproval = env.getProperty("app.merchant-auth.transfer-approval-uri",
                env.getProperty("MERCHANT_TRANSFER_APPROVAL_URI", development ? "kesorbank://merchant/transfer" : ""));
        transferCallback = env.getProperty("app.merchant-auth.transfer-callback-uri",
                env.getProperty("MERCHANT_TRANSFER_CALLBACK_URI", development ? "kesormerchant://transfer/callback" : ""));
        transfersEnabled = enabled && !transferApproval.isBlank() && !transferCallback.isBlank();
        String configuredKey = env.getProperty("app.merchant-auth.recovery-key", env.getProperty("MERCHANT_AUTH_RECOVERY_KEY", ""));
        // Domain-separated derivation is permitted only in development. Production
        // requires an independently generated encryption key, separate from JWT signing.
        recoveryKey = configuredKey.isBlank() && development
                ? MerchantAuthCrypto.developmentKey(env.getRequiredProperty("app.jwt.secret")) : configuredKey;
        if (enabled) {
            checkLink(callback, development, "kesormerchant://auth/callback");
            checkLink(approval, development, "kesorbank://merchant/approve");
            if (transfersEnabled) {
                checkLink(transferCallback, development, "kesormerchant://transfer/callback");
                checkLink(transferApproval, development, "kesorbank://merchant/transfer");
            }
            byte[] key = Base64.getDecoder().decode(recoveryKey);
            if (key.length != 32 || (!development && java.security.MessageDigest.isEqual(key,
                    Base64.getDecoder().decode(env.getRequiredProperty("app.jwt.secret")))))
                throw new IllegalArgumentException("Merchant recovery requires a separate 256-bit key");
        }
    }
    private void checkLink(String raw, boolean dev, String devLink) {
        URI uri = URI.create(raw);
        if (raw.length() > 500 || uri.getRawQuery() != null || uri.getRawFragment() != null || uri.getUserInfo() != null
                || !(dev && raw.equals(devLink) || "https".equals(uri.getScheme())
                    && uri.getHost() != null && uri.getPath() != null && !uri.getPath().isBlank()))
            throw new IllegalArgumentException("Merchant links must be exact registered HTTPS URLs (or development links)");
    }
    public void requireEnabled() {
        if (!enabled) throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "MERCHANT_AUTH_UNAVAILABLE", "Merchant sign-in is unavailable");
    }
    public void requireTransfers() {
        requireEnabled();
        if (!transfersEnabled) throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "MERCHANT_TRANSFER_UNAVAILABLE",
                "Transfers to your wallet are unavailable");
    }
    public void requireClient(String client, String redirect) {
        requireEnabled();
        if (!CLIENT.equals(client) || !callback.equals(redirect)) throw new ApiException(HttpStatus.BAD_REQUEST,
                "MERCHANT_AUTH_INVALID", "Merchant client or callback is invalid");
    }
}
