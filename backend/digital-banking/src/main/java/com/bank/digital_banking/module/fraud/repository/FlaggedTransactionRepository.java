package com.bank.digital_banking.module.fraud.repository;

import com.bank.digital_banking.module.fraud.entity.FlaggedTransaction;
import com.bank.digital_banking.module.fraud.entity.RiskLevel;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface FlaggedTransactionRepository extends JpaRepository<FlaggedTransaction, Long> {
    List<FlaggedTransaction> findByAccountId(String accountId);
    List<FlaggedTransaction> findByRiskLevel(RiskLevel riskLevel, org.springframework.data.domain.Pageable pageable);
    long countByAccountIdAndCreatedAtAfter(String accountId, LocalDateTime timestamp);
}