package com.bank.digital_banking.module.transaction.service;

import com.bank.digital_banking.common.dto.PageResponse;
import com.bank.digital_banking.common.exception.InsufficientBalanceException;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.account.entity.AccountStatus;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.transaction.dto.DepositRequestDto;
import com.bank.digital_banking.module.transaction.dto.TransactionResponseDto;
import com.bank.digital_banking.module.transaction.dto.TransferRequestDto;
import com.bank.digital_banking.module.transaction.entity.Transaction;
import com.bank.digital_banking.module.transaction.entity.TransactionStatus;
import com.bank.digital_banking.module.transaction.entity.TransactionType;
import com.bank.digital_banking.module.transaction.repository.TransactionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class TransactionService {

    private final TransactionRepository transactionRepository;
    private final AccountRepository accountRepository;

    @Transactional
    public TransactionResponseDto processTransfer(User user, TransferRequestDto request) {
        Account sourceAccount = accountRepository.findByAccountNumber(request.getSourceAccountNumber())
                .orElseThrow(() -> new ResourceNotFoundException("Source account not found"));

        Account destinationAccount = accountRepository.findByAccountNumber(request.getDestinationAccountNumber())
                .orElseThrow(() -> new ResourceNotFoundException("Destination account not found"));

        if (!sourceAccount.getUser().getId().equals(user.getId())) {
            throw new IllegalArgumentException("Unauthorized access to source account");
        }

        if (sourceAccount.getStatus() != AccountStatus.ACTIVE) {
            throw new IllegalStateException("Source account is not active");
        }

        if (destinationAccount.getStatus() != AccountStatus.ACTIVE) {
            throw new IllegalStateException("Destination account is not active");
        }

        if (sourceAccount.getAccountNumber().equals(destinationAccount.getAccountNumber())) {
            throw new IllegalArgumentException("Source and destination accounts cannot be the same");
        }

        if (!sourceAccount.getCurrency().equalsIgnoreCase(request.getCurrency()) ||
            !destinationAccount.getCurrency().equalsIgnoreCase(request.getCurrency())) {
            throw new IllegalArgumentException("Currency mismatch across transfer accounts");
        }

        if (sourceAccount.getBalance().compareTo(request.getAmount()) < 0) {
            throw new InsufficientBalanceException("Insufficient funds for this transfer");
        }

        sourceAccount.setBalance(sourceAccount.getBalance().subtract(request.getAmount()));
        destinationAccount.setBalance(destinationAccount.getBalance().add(request.getAmount()));

        accountRepository.save(sourceAccount);
        accountRepository.save(destinationAccount);

        Transaction transaction = Transaction.builder()
                .referenceNumber(generateReferenceNumber())
                .sourceAccount(sourceAccount)
                .destinationAccount(destinationAccount)
                .amount(request.getAmount())
                .fee(BigDecimal.ZERO)
                .currency(request.getCurrency().toUpperCase())
                .transactionType(TransactionType.TRANSFER)
                .status(TransactionStatus.SUCCESS)
                .remark(request.getRemark())
                .build();

        Transaction savedTransaction = transactionRepository.save(transaction);
        return TransactionResponseDto.fromEntity(savedTransaction);
    }

    @Transactional
    public TransactionResponseDto processDeposit(DepositRequestDto request) {
        Account destinationAccount = accountRepository.findByAccountNumber(request.getAccountNumber())
                .orElseThrow(() -> new ResourceNotFoundException("Account not found"));

        if (destinationAccount.getStatus() != AccountStatus.ACTIVE) {
            throw new IllegalStateException("Account is not active");
        }

        destinationAccount.setBalance(destinationAccount.getBalance().add(request.getAmount()));
        accountRepository.save(destinationAccount);

        Transaction transaction = Transaction.builder()
                .referenceNumber(generateReferenceNumber())
                .sourceAccount(null)
                .destinationAccount(destinationAccount)
                .amount(request.getAmount())
                .fee(BigDecimal.ZERO)
                .currency(request.getCurrency().toUpperCase())
                .transactionType(TransactionType.DEPOSIT)
                .status(TransactionStatus.SUCCESS)
                .remark(request.getRemark())
                .build();

        Transaction savedTransaction = transactionRepository.save(transaction);
        return TransactionResponseDto.fromEntity(savedTransaction);
    }

    @Transactional(readOnly = true)
    public PageResponse<TransactionResponseDto> getAccountTransactions(User user, String accountNumber, int page, int size) {
        Account account = accountRepository.findByAccountNumber(accountNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Account not found"));

        if (!account.getUser().getId().equals(user.getId())) {
            throw new IllegalArgumentException("Unauthorized access to account history");
        }

        Pageable pageable = PageRequest.of(page, size);
        Page<Transaction> transactionPage = transactionRepository.findAllByAccount(account, pageable);

        Page<TransactionResponseDto> dtoPage = transactionPage.map(TransactionResponseDto::fromEntity);
        return PageResponse.from(dtoPage);
    }

    @Transactional(readOnly = true)
    public TransactionResponseDto getTransactionByReference(String referenceNumber) {
        Transaction transaction = transactionRepository.findByReferenceNumber(referenceNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Transaction reference not found: " + referenceNumber));

        return TransactionResponseDto.fromEntity(transaction);
    }

    private String generateReferenceNumber() {
        String datePrefix = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        String randomUUID = UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        return "TXN-" + datePrefix + "-" + randomUUID;
    }
}