package com.bank.digital_banking.module.audit.repository;

import com.bank.digital_banking.module.audit.entity.AuditLog;
import com.bank.digital_banking.module.audit.entity.AuditSeverity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface AuditLogRepository extends JpaRepository<AuditLog, Long> {

    List<AuditLog> findByPerformerUserIdOrderByTimestampDesc(String performerUserId, org.springframework.data.domain.Pageable pageable);

    List<AuditLog> findByModuleNameOrderByTimestampDesc(String moduleName, org.springframework.data.domain.Pageable pageable);

    List<AuditLog> findBySeverityOrderByTimestampDesc(AuditSeverity severity, org.springframework.data.domain.Pageable pageable);

    List<AuditLog> findByTimestampBetweenOrderByTimestampDesc(LocalDateTime start, LocalDateTime end, org.springframework.data.domain.Pageable pageable);
}