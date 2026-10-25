package com.bank.digital_banking.module.payment.dto;

import java.math.BigDecimal;

/**
 * Preview response returned when a user scans a QR code.
 * Contains payee name, verified destination account number, currency,
 * preset amount (if dynamic), purpose, and payment validity status.
 */
public record QrScanResponse(
        boolean valid,
        String qrString,
        String qrHash,
        String destinationAccountNumber,
        String destinationAccountName,
        BigDecimal amount,
        String currency,
        boolean isDynamic,
        String acquiringBank,
        String remark,
        String billNumber,
        boolean isAlreadyPaid
) {}
