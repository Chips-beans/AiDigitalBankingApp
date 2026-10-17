package com.bank.digital_banking.module.fraud.controller;

import com.bank.digital_banking.module.fraud.dto.*;
import com.bank.digital_banking.module.fraud.entity.RiskLevel;
import com.bank.digital_banking.module.fraud.service.FraudDetectionService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/fraud")
@RequiredArgsConstructor
public class FraudRuleController {

    private final FraudDetectionService fraudDetectionService;

    @PostMapping("/check")
    public ResponseEntity<FraudCheckResponse> evaluateTransaction(@Valid @RequestBody FraudCheckRequest request) {
        return ResponseEntity.ok(fraudDetectionService.evaluateTransaction(request));
    }

    @PostMapping("/rules")
    public ResponseEntity<Void> createRule(@Valid @RequestBody FraudRuleRequest request) {
        fraudDetectionService.createRule(request);
        return ResponseEntity.status(HttpStatus.CREATED).build();
    }

    @GetMapping("/flagged")
    public ResponseEntity<List<FlaggedTransactionResponse>> getFlaggedTransactions(@RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(fraudDetectionService.getFlaggedTransactions(page, size));
    }

    @GetMapping("/flagged/risk/{riskLevel}")
    public ResponseEntity<List<FlaggedTransactionResponse>> getFlaggedTransactionsByRisk(@PathVariable RiskLevel riskLevel, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(fraudDetectionService.getFlaggedTransactionsByRisk(riskLevel, page, size));
    }
}