package com.bank.digital_banking.module.payment.dto;

import jakarta.validation.constraints.NotBlank;

public record QrScanRequest(
        @NotBlank(message = "QR code string is required")
        @jakarta.validation.constraints.Size(max = 4096)
        String qrString
) {}
