package com.bank.digital_banking.module.audit.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "audit_logs")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AuditLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String moduleName; // E.g., "PAYMENT", "AUTH", "FRAUD", "MERCHANT"

    @Column(nullable = false)
    private String action; // E.g., "TRANSFER_INITIATED", "USER_LOGIN_FAILED", "FRAUD_RULE_CREATED"

    private String performerUserId; // Account ID or Username executing the action

    private String targetResourceId; // Resource affected (e.g., Account No, Merchant ID, Rule ID)

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, columnDefinition = "audit_severity")
    @org.hibernate.annotations.JdbcTypeCode(org.hibernate.type.SqlTypes.NAMED_ENUM)
    private AuditSeverity severity;

    @Column(columnDefinition = "TEXT")
    private String details; // JSON or text payload summary

    private String ipAddress;

    @Column(name = "correlation_id", length = 36)
    private String correlationId;

    private String userAgent;

    @Column(nullable = false)
    private boolean success;

    private LocalDateTime timestamp;

    @PrePersist
    protected void onCreate() {
        if (this.timestamp == null) {
            this.timestamp = LocalDateTime.now();
        }
    }
}
