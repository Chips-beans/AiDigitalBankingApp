package com.bank.digital_banking.module.audit.aspect;

import com.bank.digital_banking.module.audit.annotation.Auditable;
import com.bank.digital_banking.module.audit.dto.AuditLogRequest;
import com.bank.digital_banking.module.audit.service.AuditService;
import lombok.RequiredArgsConstructor;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;

import org.springframework.stereotype.Component;

@Aspect
@Component
@RequiredArgsConstructor
public class AuditAspect {

    private final AuditService auditService;

    @Around("@annotation(auditable)")
    public Object auditMethodExecution(ProceedingJoinPoint joinPoint, Auditable auditable) throws Throwable {
        boolean isSuccess = false;
        Object result = null;
        try {
            result = joinPoint.proceed();
            isSuccess = true;
            return result;
        } catch (Throwable throwable) {
            isSuccess = false;
            throw throwable;
        } finally {
            AuditLogRequest logRequest = new AuditLogRequest(
                    auditable.module(),
                    auditable.action(),
                    "SYSTEM_USER", // Replace dynamically with SecurityContextHolder user if Security is present
                    null,
                    auditable.severity(),
                    "Method executed: " + joinPoint.getSignature().toShortString(),
                    "127.0.0.1",
                    "Internal System",
                    isSuccess
            );
            auditService.logEvent(logRequest);
        }
    }
}