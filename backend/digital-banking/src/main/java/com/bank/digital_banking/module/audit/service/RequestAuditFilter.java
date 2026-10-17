package com.bank.digital_banking.module.audit.service;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;
import java.io.IOException;
import java.util.UUID;
import java.util.Map;
import com.bank.digital_banking.common.dto.ApiErrorResponse;
import com.bank.digital_banking.common.exception.AuditUnavailableException;
import tools.jackson.databind.ObjectMapper;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
@RequiredArgsConstructor
public class RequestAuditFilter extends OncePerRequestFilter {
    private final AuditTrail audit;
    private final ObjectMapper json;

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/v1/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String correlation = UUID.randomUUID().toString();
        request.setAttribute(AuditTrail.CORRELATION, correlation);
        response.setHeader("X-Correlation-ID", correlation);
        // Retain request metadata until after Spring Security and MVC have unwound.
        var previous = RequestContextHolder.getRequestAttributes();
        var buffered = new ContentCachingResponseWrapper(response);
        var attributes = new ServletRequestAttributes(request, buffered);
        RequestContextHolder.setRequestAttributes(attributes);
        try {
            chain.doFilter(request, buffered);
            // Inner framework filters may clear their thread context on return.
            RequestContextHolder.setRequestAttributes(attributes);
            if (buffered.getStatus() >= 400 && !Boolean.TRUE.equals(request.getAttribute(AuditTrail.REJECTED))) {
                if (Boolean.TRUE.equals(request.getAttribute(AuditTrail.REJECTION_ATTEMPTED))) {
                    unavailable(request, buffered);
                } else {
                    try {
                        audit.rejected(AuditTrail.actor(), module(request), action(request), "HTTP_" + buffered.getStatus());
                    } catch (AuditUnavailableException | org.springframework.transaction.TransactionException
                             | org.springframework.dao.DataAccessException ex) {
                        // This runs outside MVC exception advice. Preserve a safe JSON contract
                        // even if the audit transaction cannot start or commit.
                        unavailable(request, buffered);
                    }
                }
            }
            // Do not expose a rejected response before its audit transaction has completed.
            buffered.copyBodyToResponse();
        } finally {
            RequestContextHolder.setRequestAttributes(previous);
        }
    }

    private void unavailable(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.resetBuffer();
        response.setStatus(503);
        response.setContentType("application/json");
        response.getWriter().write(json.writeValueAsString(ApiErrorResponse.of(503, "AUDIT_UNAVAILABLE",
                "Required audit storage is unavailable; try again later", request.getRequestURI(), Map.of(), null)));
    }

    private String module(HttpServletRequest request) {
        String[] path = request.getRequestURI().split("/");
        return switch (path.length > 3 ? path[3] : "") {
            case "auth" -> "AUTH";
            case "accounts" -> "ACCOUNT";
            case "transactions" -> "TRANSACTION";
            case "merchants" -> "MERCHANT";
            case "payments" -> "PAYMENT";
            case "fraud" -> "FRAUD";
            case "audit" -> "AUDIT";
            case "ai" -> "AI";
            default -> "API";
        };
    }

    private String action(HttpServletRequest request) {
        String path = request.getRequestURI();
        if (request.getMethod().equals("POST")) {
            return switch (path) {
                case "/api/v1/transactions/transfer" -> "TRANSFER";
                case "/api/v1/transactions/deposit" -> "DEPOSIT";
                case "/api/v1/auth/login" -> "LOGIN";
                case "/api/v1/auth/register" -> "REGISTER";
                case "/api/v1/auth/refresh" -> "REFRESH";
                case "/api/v1/auth/logout" -> "LOGOUT";
                case "/api/v1/auth/request-otp" -> "OTP_REQUEST";
                case "/api/v1/accounts" -> "ACCOUNT_CREATED";
                default -> "REQUEST_REJECTED";
            };
        }
        if (request.getMethod().equals("PATCH") && path.startsWith("/api/v1/accounts/") && path.endsWith("/status"))
            return "ACCOUNT_STATUS_CHANGED";
        return "REQUEST_REJECTED";
    }
}
