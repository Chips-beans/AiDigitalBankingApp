package com.bank.digital_banking.module.ai.adapter;

import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import jakarta.annotation.PostConstruct;

import java.util.List;
import java.util.Map;

@Slf4j
@Component
public class GeminiAdapter {

    private final RestClient restClient;
    private final AIProperties properties;

    public GeminiAdapter(AIProperties properties) {
        this.properties = properties;
        this.restClient = RestClient.builder()
                .baseUrl(properties.getApiUrl())
                .build();
    }
    @PostConstruct
    public void initCheck() {
        log.info("Gemini Enabled: {}, API Key Configured: {}", 
                properties.isEnabled(), 
                (properties.getApiKey() != null && !properties.getApiKey().isBlank()));
    }

    public String generateCompletion(String systemInstruction, String userPrompt) {
        if (!properties.isEnabled() || properties.getApiKey() == null || properties.getApiKey().isBlank()) {
            log.warn("Gemini API key is unconfigured or disabled.");
            return "AI service is currently unavailable.";
        }

        try {
            // Build the standard Gemini generateContent JSON payload
            Map<String, Object> requestBody = Map.of(
                    "system_instruction", Map.of(
                            "parts", List.of(Map.of("text", systemInstruction))
                    ),
                    "contents", List.of(
                            Map.of("parts", List.of(Map.of("text", userPrompt)))
                    ),
                    "generationConfig", Map.of(
                            "temperature", 0.2,
                            "maxOutputTokens", 500
                    )
            );

            Map<?, ?> response = restClient.post()
            .uri("/models/{model}:generateContent?key={key}", properties.getModel(), properties.getApiKey())
            .contentType(MediaType.APPLICATION_JSON)
            .body(requestBody)
            .retrieve()
            .body(Map.class);

            return parseGeminiResponse(response);

        } catch (Exception e) {
            log.error("Failed to generate completion from Gemini API", e);
            return "Unable to process AI request at this moment.";
        }
    }

    @SuppressWarnings("unchecked")
    private String parseGeminiResponse(Map<?, ?> response) {
        if (response != null && response.containsKey("candidates")) {
            List<?> candidates = (List<?>) response.get("candidates");
            if (!candidates.isEmpty()) {
                Map<?, ?> candidate = (Map<?, ?>) candidates.get(0);
                Map<?, ?> content = (Map<?, ?>) candidate.get("content");
                List<?> parts = (List<?>) content.get("parts");
                if (!parts.isEmpty()) {
                    Map<?, ?> firstPart = (Map<?, ?>) parts.get(0);
                    return (String) firstPart.get("text");
                }
            }
        }
        return "No output received from Gemini API.";
    }
}