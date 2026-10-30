package com.bank.digital_banking.module.transaction.service.impl;

import com.bank.digital_banking.common.dto.PageResponse;
import com.bank.digital_banking.common.exception.*;
import com.bank.digital_banking.common.util.PageBounds;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.transaction.dto.*;
import com.bank.digital_banking.module.transaction.entity.TransactionType;
import com.bank.digital_banking.module.transaction.repository.TransactionRepository;
import com.bank.digital_banking.module.transaction.service.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.function.Supplier;

@Service
@RequiredArgsConstructor
public class TransactionServiceImpl implements TransactionService {
    private final TransactionRepository transactionRepository;
    private final AccountRepository accountRepository;
    private final FinancialCommandService commands;
    private final AuditTrail audit;
    private final ExchangeRates rates;

    @Override
    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.NEVER)
    public TransactionResponseDto processTransfer(User user, TransferRequestDto request, String key,
                                                  FinancialCommandService.PinProof proof) {
        return attempt(user, "TRANSFER", () -> commands.executeTransfer(user, key,
                request.getSourceAccountNumber(), request.getDestinationAccountNumber(), request.getAmount(), request.getCurrency(),
                request.getRemark(), proof));
    }

    @Override
    @Transactional(readOnly = true)
    public ExchangeRates.Quote quote(User user, String sourceNumber, String destinationNumber, java.math.BigDecimal amount) {
        var source = accountRepository.findByAccountNumber(sourceNumber == null ? "" : sourceNumber)
                .filter(a -> a.getUser().getId().equals(user.getId()))
                .orElseThrow(() -> new ResourceNotFoundException("Account not available"));
        var destination = accountRepository.findByAccountNumber(destinationNumber == null ? "" : destinationNumber)
                .filter(a -> a.getStatus() == com.bank.digital_banking.module.account.entity.AccountStatus.ACTIVE)
                .orElseThrow(() -> new ResourceNotFoundException("Account not available"));
        return rates.forDebit(amount, source.getCurrency(), destination.getCurrency());
    }

    @Override
    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.NEVER)
    public TransactionResponseDto processDeposit(User user, DepositRequestDto request, String key) {
        return attempt(user, "DEPOSIT", () -> commands.execute(user, TransactionType.DEPOSIT, key,
                null, request.getAccountNumber(), request.getAmount(), request.getCurrency(), request.getRemark()));
    }

    private TransactionResponseDto attempt(User actor, String action, Supplier<TransactionResponseDto> work) {
        try {
            return work.get();
        } catch (RuntimeException ex) {
            // The command transaction, including balances and claim, has already rolled back.
            String outcome = ex instanceof ApiException api ? api.getCode() : ex instanceof InsufficientBalanceException ? "INSUFFICIENT_FUNDS" : "REJECTED";
            audit.rejected(actor == null ? "ANONYMOUS" : actor.getId().toString(), "TRANSACTION", action, outcome);
            throw ex;
        }
    }

    @Override
    @Transactional(readOnly = true)
    public PageResponse<TransactionResponseDto> getAccountTransactions(User user, String accountNumber, int page, int size) {
        var pageable = PageBounds.of(page, size);
        var account = accountRepository.findByAccountNumber(accountNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Account not available"));
        if (!account.getUser().getId().equals(user.getId())) throw new ResourceNotFoundException("Account not available");
        return PageResponse.from(transactionRepository.findAllByAccount(account, pageable).map(TransactionResponseDto::fromEntity));
    }

    @Override
    @Transactional(readOnly = true)
    public TransactionResponseDto getTransactionByReference(User user, String referenceNumber) {
        var transaction = transactionRepository.findByReferenceNumber(referenceNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Transaction not available"));
        boolean ownsSource = transaction.getSourceAccount() != null && transaction.getSourceAccount().getUser().getId().equals(user.getId());
        boolean ownsDestination = transaction.getDestinationAccount() != null && transaction.getDestinationAccount().getUser().getId().equals(user.getId());
        if (!ownsSource && !ownsDestination) throw new ResourceNotFoundException("Transaction not available");
        return TransactionResponseDto.fromEntity(transaction);
    }
}
