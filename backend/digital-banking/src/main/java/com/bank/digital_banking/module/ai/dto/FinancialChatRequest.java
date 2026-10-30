package com.bank.digital_banking.module.ai.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record FinancialChatRequest(
        @NotNull(message = "User ID is required")
        Long userId,

        @NotBlank(message = "Prompt message cannot be empty")
        @jakarta.validation.constraints.Size(max=2000)
        String message
) {}
