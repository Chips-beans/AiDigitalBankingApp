package com.bank.digital_banking.module.audit.dto;

import com.bank.digital_banking.module.audit.entity.AuditSeverity;
import jakarta.validation.constraints.NotBlank;

public record AuditLogRequest(
        @NotBlank(message = "Module name is required")
        String moduleName,

        @NotBlank(message = "Action is required")
        String action,

        String performerUserId,
        String targetResourceId,
        AuditSeverity severity,
        String details,
        String ipAddress,
        String userAgent,
        boolean success
) {}