package com.bank.digital_banking.module.ai.controller;

import com.bank.digital_banking.module.ai.dto.*;
import com.bank.digital_banking.module.ai.service.AIService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import com.bank.digital_banking.module.auth.entity.User;
import org.springframework.security.core.annotation.AuthenticationPrincipal;

// ===================================================================
// Added for Swagger UI categorization & documentation: AI Insights
// ===================================================================
@Tag(name = "AI Insights", description = "AI-powered financial insights, spending analysis, and chat assistant")
@RestController
@RequestMapping("/api/v1/ai")
@RequiredArgsConstructor
public class AIInsightController {

    private final AIService aiService;

    // Added: OpenAPI Operation description
    @Operation(summary = "Generate spending insight", description = "Generates AI analysis and breakdown of spending for a given target period")
    @PostMapping("/insights/spending")
    public ResponseEntity<SpendingInsightResponse> generateSpendingInsight(@AuthenticationPrincipal User user, @Valid @RequestBody SpendingInsightRequest request) {
        return ResponseEntity.ok(aiService.generateSpendingInsight(new SpendingInsightRequest(user.getId(), request.targetPeriod(), request.categorySpends())));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Ask financial assistant", description = "Chat with AI financial assistant about accounts and spending habits")
    @PostMapping("/chat")
    public ResponseEntity<FinancialChatResponse> askAssistant(@AuthenticationPrincipal User user, @Valid @RequestBody FinancialChatRequest request) {
        return ResponseEntity.ok(aiService.askFinancialAssistant(new FinancialChatRequest(user.getId(), request.message())));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Get user insights", description = "Retrieves previously generated spending insights for the authenticated user")
    @GetMapping("/insights/user/{userId}")
    public ResponseEntity<List<SpendingInsightResponse>> getUserInsights(@AuthenticationPrincipal User user, @PathVariable Long userId, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        if (!user.getId().equals(userId)) throw new com.bank.digital_banking.common.exception.ResourceNotFoundException("Insights not available");
        return ResponseEntity.ok(aiService.getUserInsights(user.getId(), page, size));
    }
}
