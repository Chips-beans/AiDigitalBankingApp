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
            "/api/v1/auth/request-otp", "/api/v1/auth/refresh");
    private final SessionService sessions;
    private final ObjectMapper json;

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getServletPath();
        return PUBLIC_AUTH.contains(path) || "OPTIONS".equals(request.getMethod())
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
                var authorities = session.getUser().getRoles().stream()
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
