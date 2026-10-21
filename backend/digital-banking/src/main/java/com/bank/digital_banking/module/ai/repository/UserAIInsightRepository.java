package com.bank.digital_banking.module.ai.repository;

import com.bank.digital_banking.module.ai.entity.InsightType;
import com.bank.digital_banking.module.ai.entity.UserAIInsight;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface UserAIInsightRepository extends JpaRepository<UserAIInsight, Long> {

    Optional<UserAIInsight> findByUserIdAndTargetPeriodAndInsightType(Long userId, String targetPeriod, InsightType insightType);

    Page<UserAIInsight> findByUserId(Long userId, Pageable pageable);
}