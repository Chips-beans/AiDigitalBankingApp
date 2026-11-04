package com.bank.digital_banking.module.ai.assistant;

import tools.jackson.databind.JsonNode;
import java.util.Map;

public interface AssistantProvider {
    boolean available();
    JsonNode classify(String sanitizedPrompt,long deadlineNanos);
    /** Writes the customer-facing text. {@code mode}: ACCOUNT (verified facts), MIXED (facts plus general guidance) or GENERAL (no customer data). */
    String compose(String sanitizedQuestion,Map<String,String> facts,String mode,String locale,long deadlineNanos);
}
