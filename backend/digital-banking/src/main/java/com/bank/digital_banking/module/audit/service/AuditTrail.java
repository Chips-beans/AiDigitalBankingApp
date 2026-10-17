package com.bank.digital_banking.module.audit.service;

import com.bank.digital_banking.module.auth.entity.User;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import java.util.UUID;
import com.bank.digital_banking.common.exception.AuditUnavailableException;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import com.bank.digital_banking.common.util.TransactionLockPolicy;

/** Writes only explicit event metadata, never request bodies or credentials. */
@Service
@RequiredArgsConstructor
public class AuditTrail {
    public static final String ACTOR = AuditTrail.class.getName() + ".actor";
    public static final String CORRELATION = AuditTrail.class.getName() + ".correlation";
    public static final String REJECTED = AuditTrail.class.getName() + ".rejected";
    public static final String REJECTION_ATTEMPTED = AuditTrail.class.getName() + ".rejectionAttempted";
    private final JdbcTemplate jdbc;
    private final TransactionLockPolicy locks;

    public static HttpServletRequest request() {
        return RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes attributes
                ? attributes.getRequest() : null;
    }

    public static String actor() {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.getPrincipal() instanceof User user) return user.getId().toString();
        var request = request();
        if (request != null) return request.getAttribute(ACTOR) instanceof String id ? id : "ANONYMOUS";
        return "SYSTEM";
    }

    public static String correlation() {
        var request = request();
        return request != null && request.getAttribute(CORRELATION) instanceof String id ? id : UUID.randomUUID().toString();
    }

    @Transactional
    public void success(String module, String action, String target) {
        write(actor(), module, action, target, true, "COMPLETED");
    }

    @Transactional
    public void successAs(User user, String module, String action, String target) {
        var request = request();
        if (request != null) {
            String actorId = user.getId().toString();
            // Registration may still roll back, so its generated ID is not an authenticated caller yet.
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override public void afterCommit() { request.setAttribute(ACTOR, actorId); }
            });
        }
        write(user.getId().toString(), module, action, target, true, "COMPLETED");
    }

    @Transactional
    public void posting(User user, String action, String reference, String correlation) {
        write(user.getId().toString(), "TRANSACTION", action, reference, true, "COMPLETED", correlation);
    }

    // Called only after the business transaction has unwound; no nested pool acquisition.
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void rejected(String actor, String module, String action, String outcome) {
        var request = request();
        if (request != null) request.setAttribute(REJECTION_ATTEMPTED, Boolean.TRUE);
        write(actor, module, action, null, false, outcome);
        if (request != null) request.setAttribute(REJECTED, Boolean.TRUE);
    }

    private void write(String actor, String module, String action, String target, boolean success, String outcome) {
        write(actor, module, action, target, success, outcome, correlation());
    }

    private void write(String actor, String module, String action, String target, boolean success, String outcome, String correlation) {
        var request = request();
        try {
            // Rejection events use their own transaction; bound that wait as well.
            locks.apply();
            jdbc.update("""
                INSERT INTO audit_logs(module_name, action, performer_user_id, target_resource_id,
                  severity, details, ip_address, user_agent, success, correlation_id)
                VALUES (?, ?, ?, ?, CAST(? AS audit_severity), ?, ?, ?, ?, ?)
                """, module, action, actor, target, success ? "INFO" : "WARN", outcome,
                request == null ? null : request.getRemoteAddr(),
                request == null ? null : bounded(request.getHeader("User-Agent"), 512), success, correlation);
        } catch (org.springframework.dao.DataAccessException ex) {
            throw new AuditUnavailableException(ex);
        }
    }

    private String bounded(String value, int limit) {
        return value == null ? null : value.substring(0, Math.min(value.length(), limit));
    }
}
