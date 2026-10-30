package com.bank.digital_banking.module.ai.assistant;

import tools.jackson.databind.JsonNode;
import java.util.Map;

public interface AssistantProvider {
    boolean available();
    JsonNode classify(String sanitizedPrompt,long deadlineNanos);
    String explain(Map<String,String> facts,String locale,long deadlineNanos);
}
