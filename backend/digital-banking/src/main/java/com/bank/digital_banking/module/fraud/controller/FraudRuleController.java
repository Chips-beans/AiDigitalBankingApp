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
    public ResponseEntity<List<FlaggedTransactionResponse>> getFlaggedTransactions() {
        return ResponseEntity.ok(fraudDetectionService.getFlaggedTransactions());
    }

    @GetMapping("/flagged/risk/{riskLevel}")
    public ResponseEntity<List<FlaggedTransactionResponse>> getFlaggedTransactionsByRisk(@PathVariable RiskLevel riskLevel) {
        return ResponseEntity.ok(fraudDetectionService.getFlaggedTransactionsByRisk(riskLevel));
    }
}