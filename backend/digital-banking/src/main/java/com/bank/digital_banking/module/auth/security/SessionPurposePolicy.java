package com.bank.digital_banking.module.auth.security;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.entity.AuthSession;
import org.springframework.http.HttpStatus;

/** Fail closed before role checks; dual-role owners cannot cross application boundaries. */
public final class SessionPurposePolicy {
    private SessionPurposePolicy() {}
    public static void requireRoute(AuthSession session, String method, String path) {
        boolean merchantRoute = ("GET".equals(method) && path.equals("/api/v1/merchant-auth/session"))
                || ("POST".equals(method) && path.equals("/api/v1/merchant-auth/logout"));
        if ("MERCHANT".equals(session.getPurpose())) {
            if (!merchantRoute) throw new ApiException(HttpStatus.FORBIDDEN, "CUSTOMER_SESSION_REQUIRED",
                    "This API is not available to a Merchant session");
        } else if (merchantRoute) throw new ApiException(HttpStatus.FORBIDDEN, "MERCHANT_SESSION_REQUIRED",
                "Use a Merchant session for this API");
    }
}
