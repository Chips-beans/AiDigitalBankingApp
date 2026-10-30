package com.bank.digital_banking.module.ai.assistant;

import org.springframework.context.annotation.*;
import java.time.Clock;

@Configuration
public class AssistantConfiguration {
    @Bean public Clock assistantClock() { return Clock.systemUTC(); }
}
