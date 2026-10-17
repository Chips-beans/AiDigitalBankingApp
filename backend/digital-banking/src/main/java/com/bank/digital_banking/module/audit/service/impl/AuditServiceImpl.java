package com.bank.digital_banking.module.audit.service.impl;

import com.bank.digital_banking.common.util.PageBounds;

import com.bank.digital_banking.module.audit.service.AuditTrail;

import com.bank.digital_banking.module.audit.dto.*;
import com.bank.digital_banking.module.audit.entity.AuditSeverity;
import com.bank.digital_banking.module.audit.repository.AuditLogRepository;
import com.bank.digital_banking.module.audit.service.AuditService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class AuditServiceImpl implements AuditService {

    private final AuditLogRepository auditLogRepository;
    private final AuditTrail audit;

    @Override
    @Transactional
    public void logEvent(AuditLogRequest request) {
        // Compatibility endpoint: record the submission, never accept fabricated actors,
        // financial outcomes, arbitrary request bodies, or credentials as audit facts.
        audit.success("AUDIT", "MANUAL_EVENT_SUBMITTED", null);
    }

    @Override
    @Transactional(readOnly = true)
    public List<AuditLogResponse> getLogsByUser(String performerUserId, int page, int size) {
        return auditLogRepository.findByPerformerUserIdOrderByTimestampDesc(performerUserId, PageBounds.descendingId(page, size)).stream()
                .map(AuditLogResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<AuditLogResponse> getLogsByModule(String moduleName, int page, int size) {
        return auditLogRepository.findByModuleNameOrderByTimestampDesc(moduleName, PageBounds.descendingId(page, size)).stream()
                .map(AuditLogResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<AuditLogResponse> getLogsBySeverity(AuditSeverity severity, int page, int size) {
        return auditLogRepository.findBySeverityOrderByTimestampDesc(severity, PageBounds.descendingId(page, size)).stream()
                .map(AuditLogResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<AuditLogResponse> getLogsByTimeRange(LocalDateTime start, LocalDateTime end, int page, int size) {
        if (start == null || end == null || start.isAfter(end)) throw new IllegalArgumentException("Invalid audit time range");
        return auditLogRepository.findByTimestampBetweenOrderByTimestampDesc(start, end, PageBounds.descendingId(page, size)).stream()
                .map(AuditLogResponse::fromEntity)
                .toList();
    }
}
