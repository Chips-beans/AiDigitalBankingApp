package com.bank.digital_banking.module.fraud.controller;

import com.bank.digital_banking.module.fraud.dto.*;
import com.bank.digital_banking.module.fraud.entity.RiskLevel;
import com.bank.digital_banking.module.fraud.service.FraudDetectionService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

// ===================================================================
// Added for Swagger UI categorization & documentation: Fraud Detection
// ===================================================================
@Tag(name = "Fraud Detection", description = "Real-time transaction fraud evaluation, rule management, and flagged alerts")
@RestController
@RequestMapping("/api/v1/fraud")
@RequiredArgsConstructor
public class FraudRuleController {

    private final FraudDetectionService fraudDetectionService;

    // Added: OpenAPI Operation description
    @Operation(summary = "Evaluate transaction risk", description = "Evaluates an in-flight transaction against configured fraud rules and returns a risk score")
    @PostMapping("/check")
    public ResponseEntity<FraudCheckResponse> evaluateTransaction(@Valid @RequestBody FraudCheckRequest request) {
        return ResponseEntity.ok(fraudDetectionService.evaluateTransaction(request));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "Create fraud rule", description = "Registers a new rule for detecting suspicious transactions")
    @PostMapping("/rules")
    public ResponseEntity<Void> createRule(@Valid @RequestBody FraudRuleRequest request) {
        fraudDetectionService.createRule(request);
        return ResponseEntity.status(HttpStatus.CREATED).build();
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "List flagged transactions", description = "Retrieves a paginated list of suspicious transactions flagged by the risk engine")
    @GetMapping("/flagged")
    public ResponseEntity<List<FlaggedTransactionResponse>> getFlaggedTransactions(@RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(fraudDetectionService.getFlaggedTransactions(page, size));
    }

    // Added: OpenAPI Operation description
    @Operation(summary = "List flagged transactions by risk level", description = "Retrieves flagged transactions filtered by severity level (LOW, MEDIUM, HIGH, CRITICAL)")
    @GetMapping("/flagged/risk/{riskLevel}")
    public ResponseEntity<List<FlaggedTransactionResponse>> getFlaggedTransactionsByRisk(@PathVariable RiskLevel riskLevel, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(fraudDetectionService.getFlaggedTransactionsByRisk(riskLevel, page, size));
    }
}