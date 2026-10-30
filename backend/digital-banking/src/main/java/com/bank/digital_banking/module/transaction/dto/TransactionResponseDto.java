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
    /** What the destination received; equals amount/currency unless the transfer was converted. */
    private BigDecimal creditAmount;
    private String creditCurrency;
    /** KHR per USD for a converted transfer, otherwise null. */
    private BigDecimal exchangeRate;
    /** Account holders' profile names; a deposit without a source account is from the bank itself. */
    private String sourceName;
    private String destinationName;
    private boolean bankSource;
    private String operation;

    public static final String BANK_NAME = "Kesor Bank";

    public static TransactionResponseDto fromEntity(Transaction transaction) {
        var source = transaction.getSourceAccount();
        var destination = transaction.getDestinationAccount();
        boolean converted = transaction.getCreditAmount() != null;
        return TransactionResponseDto.builder()
                .id(transaction.getId())
                .referenceNumber(transaction.getReferenceNumber())
                .sourceAccountNumber(source != null ? source.getAccountNumber() : null)
                .destinationAccountNumber(destination != null ? destination.getAccountNumber() : null)
                .amount(transaction.getAmount())
                .fee(transaction.getFee())
                .currency(transaction.getCurrency())
                .transactionType(transaction.getTransactionType())
                .status(transaction.getStatus())
                .remark(transaction.getRemark())
                .createdAt(transaction.getCreatedAt() == null ? null : transaction.getCreatedAt().withOffsetSameInstant(java.time.ZoneOffset.UTC))
                .creditAmount(converted ? transaction.getCreditAmount() : transaction.getAmount())
                .creditCurrency(converted ? transaction.getCreditCurrency() : transaction.getCurrency())
                .exchangeRate(converted ? transaction.getExchangeRate() : null)
                .sourceName(source == null ? BANK_NAME : displayName(source.getUser()))
                .destinationName(destination == null ? null : displayName(destination.getUser()))
                .bankSource(source == null)
                .operation(transaction.getOperation())
                .build();
    }

    public static String displayName(com.bank.digital_banking.module.auth.entity.User user) {
        if (user == null) return null;
        String name = ((user.getFirstName() == null ? "" : user.getFirstName().strip()) + " "
                + (user.getLastName() == null ? "" : user.getLastName().strip())).strip();
        return name.isEmpty() ? user.getUsername() : name;
    }
}
