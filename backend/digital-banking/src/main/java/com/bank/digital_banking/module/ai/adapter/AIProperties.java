package com.bank.digital_banking.module.ai.adapter;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Data
@Configuration
@ConfigurationProperties(prefix = "app.ai")
public class AIProperties {
    private String apiUrl;
    private String apiKey;
    private String model = "gpt-4o-mini";
    private boolean enabled = true;
}