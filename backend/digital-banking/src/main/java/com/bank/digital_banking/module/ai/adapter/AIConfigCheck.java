package com.bank.digital_banking.module.ai.adapter;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;
import java.util.List;

/**
 * The assistant moved from Gemini (GEMINI_*) to an OpenAI-compatible gateway (AI_*). Old names are not read, because a
 * Gemini key is not valid for the gateway, so an operator who still sets them is told why the assistant stays off.
 * Only variable names are logged, never values.
 */
@Component
public class AIConfigCheck {
    static final List<String> LEGACY=List.of("GEMINI_API_KEY","GEMINI_MODEL","GEMINI_ENABLED","GEMINI_CUSTOMER_CONTEXT_ENABLED");
    private static final Logger log=LoggerFactory.getLogger(AIConfigCheck.class);
    private final Environment env;
    public AIConfigCheck(Environment env) { this.env=env; }
    @EventListener(ApplicationReadyEvent.class) public void warnAboutLegacySettings() {
        var found=legacySettings(env);
        if(!found.isEmpty()) log.warn("Ignored legacy assistant settings {}: the assistant now reads AI_API_URL, AI_API_KEY, AI_MODEL, AI_ENABLED and AI_CUSTOMER_CONTEXT_ENABLED (see .env.example).",found);
    }
    public static List<String> legacySettings(Environment env) { return LEGACY.stream().filter(env::containsProperty).toList(); }
}
