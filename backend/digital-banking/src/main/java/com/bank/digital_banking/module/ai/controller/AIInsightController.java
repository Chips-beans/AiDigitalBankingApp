package com.bank.digital_banking.module.ai.controller;

import com.bank.digital_banking.module.ai.dto.*;
import com.bank.digital_banking.module.ai.service.AIService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/ai")
@RequiredArgsConstructor
public class AIInsightController {

    private final AIService aiService;

    @PostMapping("/insights/spending")
    public ResponseEntity<SpendingInsightResponse> generateSpendingInsight(@Valid @RequestBody SpendingInsightRequest request) {
        return ResponseEntity.ok(aiService.generateSpendingInsight(request));
    }

    @PostMapping("/chat")
    public ResponseEntity<FinancialChatResponse> askAssistant(@Valid @RequestBody FinancialChatRequest request) {
        return ResponseEntity.ok(aiService.askFinancialAssistant(request));
    }

    @GetMapping("/insights/user/{userId}")
    public ResponseEntity<List<SpendingInsightResponse>> getUserInsights(@PathVariable Long userId) {
        return ResponseEntity.ok(aiService.getUserInsights(userId));
    }
}