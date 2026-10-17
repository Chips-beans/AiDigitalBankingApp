package com.bank.digital_banking.module.audit.dto;

import com.bank.digital_banking.module.audit.entity.AuditLog;
import com.bank.digital_banking.module.audit.entity.AuditSeverity;

import java.time.LocalDateTime;

public record AuditLogResponse(
        Long id,
        String moduleName,
        String action,
        String performerUserId,
        String targetResourceId,
        AuditSeverity severity,
        String details,
        String ipAddress,
        boolean success,
        LocalDateTime timestamp,
        String correlationId
) {
    public static AuditLogResponse fromEntity(AuditLog entity) {
        return new AuditLogResponse(
                entity.getId(),
                entity.getModuleName(),
                entity.getAction(),
                entity.getPerformerUserId(),
                entity.getTargetResourceId(),
                entity.getSeverity(),
                entity.getDetails(),
                entity.getIpAddress(),
                entity.isSuccess(),
                entity.getTimestamp(),
                entity.getCorrelationId()
        );
    }
}