package com.bank.digital_banking.module.ai.service.impl;

import com.bank.digital_banking.common.util.PageBounds;

import com.bank.digital_banking.module.ai.adapter.OpenAIAdapter;
import com.bank.digital_banking.module.ai.dto.*;
import com.bank.digital_banking.module.ai.entity.InsightType;
import com.bank.digital_banking.module.ai.entity.UserAIInsight;
import com.bank.digital_banking.module.ai.repository.UserAIInsightRepository;
import com.bank.digital_banking.module.ai.service.AIService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class AIServiceImpl implements AIService {

    private final OpenAIAdapter openAIAdapter;
    private final UserAIInsightRepository insightRepository;

    @Override
    @Transactional
    public SpendingInsightResponse generateSpendingInsight(SpendingInsightRequest request) {
        // Return existing cached summary if generated for this period
        return insightRepository.findByUserIdAndTargetPeriodAndInsightType(
                        request.userId(), request.targetPeriod(), InsightType.SPENDING_ANALYSIS)
                .map(existing -> new SpendingInsightResponse(
                        existing.getUserId(),
                        existing.getTargetPeriod(),
                        existing.getInsightType(),
                        existing.getGeneratedContent(),
                        existing.getCreatedAt()))
                .orElseGet(() -> {
                    String systemPrompt = "You are a professional bank AI financial advisor. " +
                            "Analyze the user's spending per category and give 2-3 concise, actionable financial advice sentences. Keep tone encouraging and professional.";

                    StringBuilder userPrompt = new StringBuilder("Period: ").append(request.targetPeriod()).append("\nCategory Breakdown:\n");
                    if (request.categorySpends() != null) {
                        request.categorySpends().forEach(cs -> userPrompt.append("- ").append(cs.category()).append(": $").append(cs.amount()).append("\n"));
                    }

                    String aiAnalysis = openAIAdapter.generateCompletion(systemPrompt, userPrompt.toString());

                    UserAIInsight insight = UserAIInsight.builder()
                            .userId(request.userId())
                            .insightType(InsightType.SPENDING_ANALYSIS)
                            .targetPeriod(request.targetPeriod())
                            .generatedContent(aiAnalysis)
                            .build();

                    UserAIInsight saved = insightRepository.save(insight);

                    return new SpendingInsightResponse(
                            saved.getUserId(),
                            saved.getTargetPeriod(),
                            saved.getInsightType(),
                            saved.getGeneratedContent(),
                            saved.getCreatedAt()
                    );
                });
    }

    @Override
    public FinancialChatResponse askFinancialAssistant(FinancialChatRequest request) {
        String systemPrompt = "You are an AI assistant for a digital banking app. Answer user banking questions clearly and concisely. " +
                "Never ask for passwords, PINs, or full card numbers.";

        String reply = openAIAdapter.generateCompletion(systemPrompt, request.message());
        return new FinancialChatResponse(reply, LocalDateTime.now().toString());
    }

    @Override
    @Transactional(readOnly = true)
    public List<SpendingInsightResponse> getUserInsights(Long userId, int page, int size) {
        return insightRepository.findByUserIdOrderByCreatedAtDesc(userId, PageBounds.descendingId(page, size)).stream()
                .map(entity -> new SpendingInsightResponse(
                        entity.getUserId(),
                        entity.getTargetPeriod(),
                        entity.getInsightType(),
                        entity.getGeneratedContent(),
                        entity.getCreatedAt()
                ))
                .toList();
    }
}