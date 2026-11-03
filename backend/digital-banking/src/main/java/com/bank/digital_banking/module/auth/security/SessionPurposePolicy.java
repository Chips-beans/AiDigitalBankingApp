package com.bank.digital_banking.module.auth.security;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.entity.AuthSession;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.PathContainer;
import org.springframework.web.util.pattern.PathPattern;
import org.springframework.web.util.pattern.PathPatternParser;

import java.util.List;

/** Fail closed before role checks; dual-role owners cannot cross application boundaries. */
public final class SessionPurposePolicy {
    private SessionPurposePolicy() {}
    /**
     * Merchant-session shop routes (M4-M6). The legacy {@code /merchants/me/accounts}
     * stays a Customer-session route; Merchant wallets live under {@code /wallets}.
     */
    public static final List<String> SHOP_ROUTES = List.of("/api/v1/merchants/me",
            "/api/v1/merchants/me/registration", "/api/v1/merchants/me/profile",
            "/api/v1/merchants/me/logo-uploads", "/api/v1/merchants/me/logo",
            "/api/v1/merchants/me/dashboard", "/api/v1/merchants/me/wallets/*",
            "/api/v1/merchants/me/qr", "/api/v1/merchants/me/payment-requests",
            "/api/v1/merchants/me/payment-requests/*", "/api/v1/merchants/me/payment-requests/*/cancel",
            "/api/v1/merchants/me/sales", "/api/v1/merchants/me/sales/*",
            "/api/v1/merchants/me/reports/collections");
    private static final List<PathPattern> PATTERNS =
            SHOP_ROUTES.stream().map(PathPatternParser.defaultInstance::parse).toList();

    public static boolean shopRoute(String path) {
        var container = PathContainer.parsePath(path);
        return PATTERNS.stream().anyMatch(p -> p.matches(container));
    }

    public static void requireRoute(AuthSession session, String method, String path) {
        boolean merchantRoute = ("GET".equals(method) && path.equals("/api/v1/merchant-auth/session"))
                || ("POST".equals(method) && path.equals("/api/v1/merchant-auth/logout"))
                || shopRoute(path);
        if ("MERCHANT".equals(session.getPurpose())) {
            if (!merchantRoute) throw new ApiException(HttpStatus.FORBIDDEN, "CUSTOMER_SESSION_REQUIRED",
                    "This API is not available to a Merchant session");
        } else if (merchantRoute) throw new ApiException(HttpStatus.FORBIDDEN, "MERCHANT_SESSION_REQUIRED",
                "Use a Merchant session for this API");
    }
}
