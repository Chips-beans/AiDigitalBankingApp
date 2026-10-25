package com.bank.digital_banking.module.payment.dto;

import com.bank.digital_banking.module.payment.entity.PaymentStatus;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Map;

/**
 * Detailed response containing the full EMVCo QR code string, tracking hash,
 * and decomposed payload data needed to render or generate the QR code on client side.
 */
public record QrGenerateResponse(
        String qrString,
        String qrHash,
        String md5Hash, // Alias for backward compatibility
        String accountNumber,
        String payeeName,
        BigDecimal amount,
        String currency,
        String qrType,
        PaymentStatus status,
        String remark,
        String billNumber,
        String acquiringBank,
        Map<String, String> payloadComponents,
        LocalDateTime createdAt
) {}
