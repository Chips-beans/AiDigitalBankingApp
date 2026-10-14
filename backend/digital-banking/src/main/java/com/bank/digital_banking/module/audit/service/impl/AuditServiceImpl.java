package com.bank.digital_banking.module.audit.service.impl;

import com.bank.digital_banking.module.audit.dto.*;
import com.bank.digital_banking.module.audit.entity.AuditLog;
import com.bank.digital_banking.module.audit.entity.AuditSeverity;
import com.bank.digital_banking.module.audit.repository.AuditLogRepository;
import com.bank.digital_banking.module.audit.service.AuditService;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class AuditServiceImpl implements AuditService {

    private final AuditLogRepository auditLogRepository;

    @Async
    @Override
    @Transactional
    public void logEvent(AuditLogRequest request) {
        AuditLog auditLog = AuditLog.builder()
                .moduleName(request.moduleName())
                .action(request.action())
                .performerUserId(request.performerUserId())
                .targetResourceId(request.targetResourceId())
                .severity(request.severity() != null ? request.severity() : AuditSeverity.INFO)
                .details(request.details())
                .ipAddress(request.ipAddress())
                .userAgent(request.userAgent())
                .success(request.success())
                .build();

        auditLogRepository.save(auditLog);
    }

    @Override
    @Transactional(readOnly = true)
    public List<AuditLogResponse> getLogsByUser(String performerUserId) {
        return auditLogRepository.findByPerformerUserIdOrderByTimestampDesc(performerUserId).stream()
                .map(AuditLogResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<AuditLogResponse> getLogsByModule(String moduleName) {
        return auditLogRepository.findByModuleNameOrderByTimestampDesc(moduleName).stream()
                .map(AuditLogResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<AuditLogResponse> getLogsBySeverity(AuditSeverity severity) {
        return auditLogRepository.findBySeverityOrderByTimestampDesc(severity).stream()
                .map(AuditLogResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<AuditLogResponse> getLogsByTimeRange(LocalDateTime start, LocalDateTime end) {
        return auditLogRepository.findByTimestampBetweenOrderByTimestampDesc(start, end).stream()
                .map(AuditLogResponse::fromEntity)
                .toList();
    }
}