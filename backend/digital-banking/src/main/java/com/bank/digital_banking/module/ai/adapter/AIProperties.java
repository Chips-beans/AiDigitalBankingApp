package com.bank.digital_banking.module.ai.adapter;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Data
@Configuration
@ConfigurationProperties(prefix = "app.ai.gemini")
public class AIProperties {
    private String apiUrl = "https://generativelanguage.googleapis.com/v1beta";
    private String apiKey;
    private String model = "gemini-3.8-flash";
    private boolean enabled = false;
    // Operator assertion: billing/data handling reviewed before customer context is enabled.
    private boolean customerContextEnabled = false;
    private int minuteLimit = 10;
    private int dailyLimit = 100;
}
