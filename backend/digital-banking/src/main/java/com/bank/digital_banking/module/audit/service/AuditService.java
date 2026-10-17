package com.bank.digital_banking.module.audit.service;

import com.bank.digital_banking.module.audit.dto.*;
import com.bank.digital_banking.module.audit.entity.AuditSeverity;

import java.time.LocalDateTime;
import java.util.List;

public interface AuditService {
    void logEvent(AuditLogRequest request);
    List<AuditLogResponse> getLogsByUser(String performerUserId, int page, int size);
    List<AuditLogResponse> getLogsByModule(String moduleName, int page, int size);
    List<AuditLogResponse> getLogsBySeverity(AuditSeverity severity, int page, int size);
    List<AuditLogResponse> getLogsByTimeRange(LocalDateTime start, LocalDateTime end, int page, int size);
}