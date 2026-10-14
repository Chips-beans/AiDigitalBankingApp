package com.bank.digital_banking.module.fraud.entity;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "fraud_rules")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class FraudRule {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String ruleCode; // E.g., "MAX_SINGLE_TX_AMOUNT"

    @Column(nullable = false)
    private String ruleName;

    private String description;

    @Column(precision = 19, scale = 2)
    private BigDecimal thresholdValue;

    private Integer velocityLimit; // Max count allowed in time window

    private Integer windowMinutes; // Time window in minutes

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private FraudAction actionToTake;

    @Builder.Default
    private boolean active = true;

    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }
}