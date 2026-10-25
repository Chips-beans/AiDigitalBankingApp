package com.bank.digital_banking.module.ai.service.impl;

import com.bank.digital_banking.module.ai.adapter.GeminiAdapter;
import com.bank.digital_banking.module.ai.dto.*;
import com.bank.digital_banking.module.ai.entity.InsightType;
import com.bank.digital_banking.module.ai.entity.UserAIInsight;
import com.bank.digital_banking.module.ai.repository.UserAIInsightRepository;
import com.bank.digital_banking.module.ai.service.AIService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class AIServiceImpl implements AIService {

    private final GeminiAdapter geminiAdapter;
    private final UserAIInsightRepository insightRepository;

    @Override
    @Transactional
    public SpendingInsightResponse generateSpendingInsight(SpendingInsightRequest request) {
        return insightRepository.findByUserIdAndTargetPeriodAndInsightType(
                        request.userId(), request.targetPeriod(), InsightType.SPENDING_ANALYSIS)
                .map(existing -> new SpendingInsightResponse(
                        existing.getUserId(),
                        existing.getTargetPeriod(),
                        existing.getInsightType(),
                        existing.getGeneratedContent(),
                        existing.getCreatedAt()))
                .orElseGet(() -> {
                    String systemPrompt = "You are an official digital banking financial advisor AI. " +
                            "Analyze the user's spending trends and give 2 concise, professional financial tips. " +
                            "Do not ask for confidential account information.";

                    StringBuilder userPrompt = new StringBuilder("Target Period: ").append(request.targetPeriod()).append("\nCategory Breakdown:\n");
                    if (request.categorySpends() != null) {
                        request.categorySpends().forEach(cs -> userPrompt.append("- ").append(cs.category()).append(": $").append(cs.amount()).append("\n"));
                    }

                    String aiAnalysis = geminiAdapter.generateCompletion(systemPrompt, userPrompt.toString());

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
        String systemPrompt = "You are a customer assistant for a digital banking mobile application. " +
                "Answer customer inquiries concisely and safely. Never ask for PINs, OTPs, or passwords.";

        String reply = geminiAdapter.generateCompletion(systemPrompt, request.message());
        return new FinancialChatResponse(reply, LocalDateTime.now().toString());
    }

    // =========================================================================
    // IMPLEMENTATION FOR getUserInsights
    // =========================================================================
    @Override
    @Transactional(readOnly = true)
    public List<SpendingInsightResponse> getUserInsights(Long userId, int page, int size) {
        Pageable pageable = com.bank.digital_banking.common.util.PageBounds.of(page, size)
                .withSort(Sort.by(Sort.Direction.DESC, "createdAt"));

        return insightRepository.findByUserId(userId, pageable)
                .stream()
                .map(insight -> new SpendingInsightResponse(
                        insight.getUserId(),
                        insight.getTargetPeriod(),
                        insight.getInsightType(),
                        insight.getGeneratedContent(),
                        insight.getCreatedAt()
                ))
                .toList();
    }
}