package com.bank.digital_banking.module.transaction.service;

import com.bank.digital_banking.common.dto.PageResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.transaction.dto.DepositRequestDto;
import com.bank.digital_banking.module.transaction.dto.TransactionResponseDto;
import com.bank.digital_banking.module.transaction.dto.TransferRequestDto;

public interface TransactionService {

    TransactionResponseDto processTransfer(User user, TransferRequestDto request, String idempotencyKey);

    TransactionResponseDto processDeposit(User user, DepositRequestDto request, String idempotencyKey);

    PageResponse<TransactionResponseDto> getAccountTransactions(User user, String accountNumber, int page, int size);

    TransactionResponseDto getTransactionByReference(User user, String referenceNumber);
}
