package com.bank.digital_banking.module.transaction.dto;

import com.bank.digital_banking.module.transaction.entity.Transaction;
import com.bank.digital_banking.module.transaction.entity.TransactionStatus;
import com.bank.digital_banking.module.transaction.entity.TransactionType;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TransactionResponseDto {

    private Long id;
    private String referenceNumber;
    private String sourceAccountNumber;
    private String destinationAccountNumber;
    private BigDecimal amount;
    private BigDecimal fee;
    private String currency;
    private TransactionType transactionType;
    private TransactionStatus status;
    private String remark;
    private OffsetDateTime createdAt;

    public static TransactionResponseDto fromEntity(Transaction transaction) {
        return TransactionResponseDto.builder()
                .id(transaction.getId())
                .referenceNumber(transaction.getReferenceNumber())
                .sourceAccountNumber(transaction.getSourceAccount() != null ? transaction.getSourceAccount().getAccountNumber() : null)
                .destinationAccountNumber(transaction.getDestinationAccount() != null ? transaction.getDestinationAccount().getAccountNumber() : null)
                .amount(transaction.getAmount())
                .fee(transaction.getFee())
                .currency(transaction.getCurrency())
                .transactionType(transaction.getTransactionType())
                .status(transaction.getStatus())
                .remark(transaction.getRemark())
                .createdAt(transaction.getCreatedAt() == null ? null : transaction.getCreatedAt().withOffsetSameInstant(java.time.ZoneOffset.UTC))
                .build();
    }
}
