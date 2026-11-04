package com.bank.digital_banking.module.ai.adapter;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Data
@Configuration
@ConfigurationProperties(prefix = "app.ai.gateway")
public class AIProperties {
    // OpenAI-compatible base URL including /v1; requests go to {apiUrl}/chat/completions.
    private String apiUrl = "https://api.groq.com/openai/v1";
    private String apiKey;
    // Must exactly match an id returned by GET {apiUrl}/models for the key.
    private String model = "qwen/qwen3.8-27b";
    // How JSON is requested: "schema" (strict json_schema, Groq gpt-oss/qwen models), "object" (json_object), "prompt" (instructions only).
    private String jsonMode = "schema";
    // Sent as reasoning_effort when not blank: qwen accepts none|default|low|medium|high, gpt-oss only low|medium|high.
    private String reasoningEffort = "none";
    private boolean enabled = false;
    // Operator assertion: billing/data handling reviewed before customer context is enabled.
    private boolean customerContextEnabled = false;
    private int minuteLimit = 10;
    private int dailyLimit = 100;
}
