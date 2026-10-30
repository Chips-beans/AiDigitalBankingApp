package com.bank.digital_banking.module.transaction.service;

import com.bank.digital_banking.common.dto.PageResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.transaction.dto.DepositRequestDto;
import com.bank.digital_banking.module.transaction.dto.TransactionResponseDto;
import com.bank.digital_banking.module.transaction.dto.TransferRequestDto;

public interface TransactionService {

    default TransactionResponseDto processTransfer(User user, TransferRequestDto request, String idempotencyKey) {
        return processTransfer(user, request, idempotencyKey, null);
    }

    TransactionResponseDto processTransfer(User user, TransferRequestDto request, String idempotencyKey,
                                           com.bank.digital_banking.module.transaction.service.FinancialCommandService.PinProof proof);

    /** Exact amounts a transfer would debit and credit, including fixed-rate conversion. */
    ExchangeRates.Quote quote(User user, String sourceAccountNumber, String destinationAccountNumber,
                              java.math.BigDecimal amount);

    TransactionResponseDto processDeposit(User user, DepositRequestDto request, String idempotencyKey);

    PageResponse<TransactionResponseDto> getAccountTransactions(User user, String accountNumber, int page, int size);

    TransactionResponseDto getTransactionByReference(User user, String referenceNumber);
}
