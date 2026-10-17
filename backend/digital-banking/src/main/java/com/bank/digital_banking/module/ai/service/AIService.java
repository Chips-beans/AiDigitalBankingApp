package com.bank.digital_banking.module.ai.service;

import com.bank.digital_banking.module.ai.dto.*;

import java.util.List;

public interface AIService {
    SpendingInsightResponse generateSpendingInsight(SpendingInsightRequest request);
    FinancialChatResponse askFinancialAssistant(FinancialChatRequest request);
    List<SpendingInsightResponse> getUserInsights(Long userId, int page, int size);
}