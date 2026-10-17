package com.bank.digital_banking.module.fraud.service;

import com.bank.digital_banking.module.fraud.dto.*;
import com.bank.digital_banking.module.fraud.entity.RiskLevel;

import java.util.List;

public interface FraudDetectionService {
    FraudCheckResponse evaluateTransaction(FraudCheckRequest request);
    void createRule(FraudRuleRequest request);
    List<FlaggedTransactionResponse> getFlaggedTransactions(int page, int size);
    List<FlaggedTransactionResponse> getFlaggedTransactionsByRisk(RiskLevel riskLevel, int page, int size);
}