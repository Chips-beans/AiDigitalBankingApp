package com.bank.digital_banking.module.auth.security;

import com.bank.digital_banking.module.audit.service.AuditTrail;

import com.bank.digital_banking.common.dto.ApiErrorResponse;
import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.auth.entity.AuthSession;
import com.bank.digital_banking.module.auth.service.SessionService;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import tools.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.util.Map;
import java.util.Set;

@Component @RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {
    private static final Set<String> PUBLIC_AUTH = Set.of("/api/v1/auth/login", "/api/v1/auth/register",
            "/api/v1/auth/request-otp", "/api/v1/auth/refresh", "/api/v1/auth/email/request",
            "/api/v1/auth/email/verify", "/api/v1/auth/telegram/start", "/api/v1/auth/telegram/exchange",
            "/api/v1/auth/telegram/callback", "/api/v1/auth/telegram/native/start", "/api/v1/auth/telegram/native/exchange",
            "/api/v1/auth/pin/home-preview", "/api/v1/auth/pin/status", "/api/v1/auth/pin/setup", "/api/v1/auth/pin/unlock", "/api/v1/auth/pin/discard");
    private final SessionService sessions;
    private final ObjectMapper json;

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getServletPath();
        boolean publicMerchant = "POST".equals(request.getMethod()) &&
                (Set.of("/api/v1/merchant-auth/attempts", "/api/v1/merchant-auth/exchange", "/api/v1/merchant-auth/refresh").contains(path)
                 || path.matches("/api/v1/merchant-auth/attempts/[0-9a-fA-F-]{36}/(status|cancel)"));
        return PUBLIC_AUTH.contains(path) || publicMerchant || "OPTIONS".equals(request.getMethod())
                || path.startsWith("/v3/api-docs") || path.startsWith("/swagger-ui");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null) {
            try {
                if (!header.startsWith("Bearer ") || header.length() <= 7)
                    throw new com.bank.digital_banking.common.exception.AuthenticationFailedException("TOKEN_INVALID", "A Bearer access token is required");
                AuthSession session = sessions.authenticate(header.substring(7));
                SessionPurposePolicy.requireRoute(session, request.getMethod(), request.getServletPath());
                if (sessions.isPinLocked(session.getId()) && !request.getServletPath().startsWith("/api/v1/auth/pin/")
                        && !request.getServletPath().equals("/api/v1/auth/logout"))
                    throw new ApiException(org.springframework.http.HttpStatus.FORBIDDEN, "PIN_REQUIRED", "Unlock the app with your PIN");
                var authorities = "MERCHANT".equals(session.getPurpose())
                        ? java.util.List.of(new SimpleGrantedAuthority("MERCHANT_SESSION"))
                        : session.getUser().getRoles().stream()
                        .filter(r -> session.getUser().isProfileComplete())
                        .map(r -> new SimpleGrantedAuthority(r.getName().name())).toList();
                var auth = UsernamePasswordAuthenticationToken.authenticated(session.getUser(), null, authorities);
                auth.setDetails(session.getId());
                SecurityContextHolder.getContext().setAuthentication(auth);
                request.setAttribute(AuditTrail.ACTOR, session.getUser().getId().toString());
            } catch (ApiException ex) {
                SecurityContextHolder.clearContext();
                response.setStatus(ex.getStatus().value());
                response.setContentType("application/json");
                response.getWriter().write(json.writeValueAsString(ApiErrorResponse.of(ex.getStatus().value(),
                        ex.getCode(), ex.getMessage(), request.getRequestURI(), Map.of(), null)));
                return;
            }
        }
        chain.doFilter(request, response);
    }
}
