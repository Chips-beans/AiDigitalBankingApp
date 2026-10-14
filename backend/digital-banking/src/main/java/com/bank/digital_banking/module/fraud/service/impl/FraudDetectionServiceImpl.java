package com.bank.digital_banking.module.fraud.service.impl;

import com.bank.digital_banking.module.fraud.adapter.GeoLocationAdapter;
import com.bank.digital_banking.module.fraud.adapter.RiskEngineAdapter;
import com.bank.digital_banking.module.fraud.dto.*;
import com.bank.digital_banking.module.fraud.entity.*;
import com.bank.digital_banking.module.fraud.repository.FlaggedTransactionRepository;
import com.bank.digital_banking.module.fraud.repository.FraudRuleRepository;
import com.bank.digital_banking.module.fraud.service.FraudDetectionService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class FraudDetectionServiceImpl implements FraudDetectionService {

    private final FraudRuleRepository fraudRuleRepository;
    private final FlaggedTransactionRepository flaggedTransactionRepository;
    private final GeoLocationAdapter geoLocationAdapter;
    private final RiskEngineAdapter riskEngineAdapter;

    private static final BigDecimal HIGH_AMOUNT_THRESHOLD = new BigDecimal("10000.00");
    private static final int VELOCITY_WINDOW_MINUTES = 10;
    private static final int MAX_VELOCITY_COUNT = 5;

    @Override
    @Transactional
    public FraudCheckResponse evaluateTransaction(FraudCheckRequest request) {

        // Rule 1: High Amount Threshold Check
        if (request.amount().compareTo(HIGH_AMOUNT_THRESHOLD) > 0) {
            logFlaggedTransaction(request, "AMOUNT_EXCEEDS_LIMIT", "Transaction amount exceeds single limit of $10,000", RiskLevel.HIGH, FraudAction.BLOCK);
            return new FraudCheckResponse(request.transactionRef(), RiskLevel.HIGH, FraudAction.BLOCK, "Transaction amount exceeds single allowed threshold", false);
        }

        // Rule 2: Velocity Check (Too many transactions in short window)
        LocalDateTime windowStart = LocalDateTime.now().minusMinutes(VELOCITY_WINDOW_MINUTES);
        long recentTxCount = flaggedTransactionRepository.countByAccountIdAndCreatedAtAfter(request.accountId(), windowStart);
        if (recentTxCount >= MAX_VELOCITY_COUNT) {
            logFlaggedTransaction(request, "VELOCITY_EXCEEDED", "Exceeded velocity limit in 10 minutes", RiskLevel.MEDIUM, FraudAction.REQUIRE_2FA);
            return new FraudCheckResponse(request.transactionRef(), RiskLevel.MEDIUM, FraudAction.REQUIRE_2FA, "High transaction velocity detected, 2FA required", false);
        }

        // Rule 3: Geo/IP Risk Check
        if (request.ipAddress() != null && geoLocationAdapter.isHighRiskIp(request.ipAddress())) {
            logFlaggedTransaction(request, "SUSPICIOUS_IP", "Transaction attempted from suspicious IP", RiskLevel.MEDIUM, FraudAction.FLAG);
            return new FraudCheckResponse(request.transactionRef(), RiskLevel.MEDIUM, FraudAction.FLAG, "Flagged for IP risk review", true);
        }

        // Rule 4: External Risk Engine ML Scoring Check
        RiskLevel externalRiskLevel = riskEngineAdapter.evaluateExternalRiskScore(request);
        if (externalRiskLevel == RiskLevel.CRITICAL) {
            logFlaggedTransaction(request, "ML_CRITICAL_RISK", "External risk engine identified critical risk score", RiskLevel.CRITICAL, FraudAction.BLOCK);
            return new FraudCheckResponse(request.transactionRef(), RiskLevel.CRITICAL, FraudAction.BLOCK, "Blocked by automated ML risk engine", false);
        } else if (externalRiskLevel == RiskLevel.HIGH) {
            logFlaggedTransaction(request, "ML_HIGH_RISK", "External risk engine identified high risk score", RiskLevel.HIGH, FraudAction.REQUIRE_2FA);
            return new FraudCheckResponse(request.transactionRef(), RiskLevel.HIGH, FraudAction.REQUIRE_2FA, "High risk score from risk engine, 2FA required", false);
        }

        return new FraudCheckResponse(request.transactionRef(), RiskLevel.LOW, FraudAction.ALLOW, "Transaction approved", true);
    }

    @Override
    @Transactional
    public void createRule(FraudRuleRequest request) {
        FraudRule rule = FraudRule.builder()
                .ruleCode(request.ruleCode())
                .ruleName(request.ruleName())
                .description(request.description())
                .thresholdValue(request.thresholdValue())
                .velocityLimit(request.velocityLimit())
                .windowMinutes(request.windowMinutes())
                .actionToTake(request.actionToTake())
                .active(true)
                .build();
        fraudRuleRepository.save(rule);
    }

    @Override
    @Transactional(readOnly = true)
    public List<FlaggedTransactionResponse> getFlaggedTransactions() {
        return flaggedTransactionRepository.findAll().stream()
                .map(FlaggedTransactionResponse::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<FlaggedTransactionResponse> getFlaggedTransactionsByRisk(RiskLevel riskLevel) {
        return flaggedTransactionRepository.findByRiskLevel(riskLevel).stream()
                .map(FlaggedTransactionResponse::fromEntity)
                .toList();
    }

    private void logFlaggedTransaction(FraudCheckRequest req, String ruleCode, String reason, RiskLevel risk, FraudAction action) {
        FlaggedTransaction ft = FlaggedTransaction.builder()
                .transactionRef(req.transactionRef())
                .accountId(req.accountId())
                .amount(req.amount())
                .currency(req.currency())
                .triggeredRuleCode(ruleCode)
                .reason(reason)
                .riskLevel(risk)
                .actionTaken(action)
                .ipAddress(req.ipAddress())
                .deviceId(req.deviceId())
                .build();
        flaggedTransactionRepository.save(ft);
    }

}