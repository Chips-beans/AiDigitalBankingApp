package com.bank.digital_banking.module.payment.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record QrTransferResponse(
        String referenceNumber,
        String status,
        String sourceAccountNumber,
        String destinationAccountNumber,
        String destinationAccountName,
        BigDecimal amount,
        String currency,
        String remark,
        LocalDateTime timestamp
) {}
