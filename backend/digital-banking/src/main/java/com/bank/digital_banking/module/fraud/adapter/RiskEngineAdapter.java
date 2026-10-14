package com.bank.digital_banking.module.fraud.adapter;

import com.bank.digital_banking.module.fraud.dto.FraudCheckRequest;
import com.bank.digital_banking.module.fraud.entity.RiskLevel;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.Map;

@Component
public class RiskEngineAdapter {

    private final RestClient restClient;
    private final boolean riskEngineEnabled;

    public RiskEngineAdapter(
            @Value("${app.fraud.risk-engine.url:https://api.risk-engine.internal}") String url,
            @Value("${app.fraud.risk-engine.enabled:false}") boolean riskEngineEnabled) {
        
        this.riskEngineEnabled = riskEngineEnabled;
        this.restClient = RestClient.builder()
                .baseUrl(url)
                .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .build();
    }

    /**
     * Sends transaction parameters to external ML risk engine to evaluate risk score (0 - 100).
     */
    public RiskLevel evaluateExternalRiskScore(FraudCheckRequest request) {
        if (!riskEngineEnabled) {
            // Fallback to LOW if external risk engine service is turned off in config
            return RiskLevel.LOW;
        }

        try {
            Map<String, Object> payload = Map.of(
                    "transactionRef", request.transactionRef(),
                    "accountId", request.accountId(),
                    "amount", request.amount(),
                    "currency", request.currency(),
                    "ipAddress", request.ipAddress() != null ? request.ipAddress() : "",
                    "deviceId", request.deviceId() != null ? request.deviceId() : ""
            );

            Map<?, ?> response = restClient.post()
                    .uri("/v1/evaluate-risk")
                    .body(payload)
                    .retrieve()
                    .body(Map.class);

            if (response != null && response.containsKey("riskScore")) {
                double score = ((Number) response.get("riskScore")).doubleValue();
                return mapScoreToRiskLevel(score);
            }
        } catch (Exception e) {
            // Log error & fallback gracefully without blocking core payment pipeline
            return RiskLevel.LOW;
        }

        return RiskLevel.LOW;
    }

    private RiskLevel mapScoreToRiskLevel(double score) {
        if (score >= 85.0) {
            return RiskLevel.CRITICAL;
        } else if (score >= 65.0) {
            return RiskLevel.HIGH;
        } else if (score >= 40.0) {
            return RiskLevel.MEDIUM;
        } else {
            return RiskLevel.LOW;
        }
    }
}