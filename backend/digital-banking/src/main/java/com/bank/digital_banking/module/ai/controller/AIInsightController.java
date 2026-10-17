package com.bank.digital_banking.module.ai.controller;

import com.bank.digital_banking.module.ai.dto.*;
import com.bank.digital_banking.module.ai.service.AIService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import com.bank.digital_banking.module.auth.entity.User;
import org.springframework.security.core.annotation.AuthenticationPrincipal;

@RestController
@RequestMapping("/api/v1/ai")
@RequiredArgsConstructor
public class AIInsightController {

    private final AIService aiService;

    @PostMapping("/insights/spending")
    public ResponseEntity<SpendingInsightResponse> generateSpendingInsight(@AuthenticationPrincipal User user, @Valid @RequestBody SpendingInsightRequest request) {
        return ResponseEntity.ok(aiService.generateSpendingInsight(new SpendingInsightRequest(user.getId(), request.targetPeriod(), request.categorySpends())));
    }

    @PostMapping("/chat")
    public ResponseEntity<FinancialChatResponse> askAssistant(@AuthenticationPrincipal User user, @Valid @RequestBody FinancialChatRequest request) {
        return ResponseEntity.ok(aiService.askFinancialAssistant(new FinancialChatRequest(user.getId(), request.message())));
    }

    @GetMapping("/insights/user/{userId}")
    public ResponseEntity<List<SpendingInsightResponse>> getUserInsights(@AuthenticationPrincipal User user, @PathVariable Long userId, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        if (!user.getId().equals(userId)) throw new com.bank.digital_banking.common.exception.ResourceNotFoundException("Insights not available");
        return ResponseEntity.ok(aiService.getUserInsights(user.getId(), page, size));
    }
}
