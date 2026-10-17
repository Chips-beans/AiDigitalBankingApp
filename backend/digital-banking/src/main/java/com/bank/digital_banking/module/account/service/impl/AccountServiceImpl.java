package com.bank.digital_banking.module.account.service.impl;

import com.bank.digital_banking.common.util.PageBounds;

import com.bank.digital_banking.common.util.CurrencyUtils;

import com.bank.digital_banking.module.audit.service.AuditTrail;

import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.module.account.dto.AccountResponseDto;
import com.bank.digital_banking.module.account.dto.CreateAccountRequestDto;
import com.bank.digital_banking.module.account.dto.UpdateAccountStatusDto;
import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.account.entity.AccountStatus;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.account.service.AccountService;
import com.bank.digital_banking.module.auth.entity.User;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.util.List;

@Service
@RequiredArgsConstructor
public class AccountServiceImpl implements AccountService {

    private final AccountRepository accountRepository;
    private final AuditTrail audit;
    private final jakarta.persistence.EntityManager entities;
    private final com.bank.digital_banking.common.util.TransactionLockPolicy locks;
    private static final SecureRandom RANDOM = new SecureRandom();

    @Override
    @Transactional
    public AccountResponseDto createAccount(User user, CreateAccountRequestDto request) {
        String currency = CurrencyUtils.currency(request.getCurrency());
        CurrencyUtils.amount(request.getInitialDeposit(), currency, true);
        if (request.getInitialDeposit().signum() != 0) {
            throw new com.bank.digital_banking.common.exception.ApiException(org.springframework.http.HttpStatus.BAD_REQUEST,
                    "VERIFIED_FUNDING_REQUIRED", "New accounts must start at zero; use a verified funding process");
        }
        String accountNumber = generateUniqueAccountNumber();

        Account account = Account.builder()
                .user(user)
                .accountNumber(accountNumber)
                .accountType(request.getAccountType())
                .currency(currency)
                .balance(request.getInitialDeposit())
                .status(AccountStatus.ACTIVE)
                .build();

        Account savedAccount = accountRepository.save(account);
        audit.successAs(user, "ACCOUNT", "ACCOUNT_CREATED", savedAccount.getAccountNumber());
        return AccountResponseDto.fromEntity(savedAccount);
    }

    @Override
    @Transactional(readOnly = true)
    public List<AccountResponseDto> getUserAccounts(User user, int page, int size) {
        return accountRepository.findByUser(user, PageBounds.ascendingId(page, size))
                .stream()
                .map(AccountResponseDto::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public AccountResponseDto getAccountByNumber(User user, String accountNumber) {
        Account account = accountRepository.findByAccountNumber(accountNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Account not found: " + accountNumber));

        if (!account.getUser().getId().equals(user.getId())) {
            throw new ResourceNotFoundException("Account not found: " + accountNumber);
        }

        return AccountResponseDto.fromEntity(account);
    }

    @Override
    @Transactional
    public AccountResponseDto updateAccountStatus(User user, String accountNumber, UpdateAccountStatusDto request) {
        boolean staff = user.getRoles().stream().anyMatch(role ->
                role.getName() == com.bank.digital_banking.module.auth.entity.ERole.ROLE_ADMIN
                        || role.getName() == com.bank.digital_banking.module.auth.entity.ERole.ROLE_BANK_EMPLOYEE);
        if (!staff) throw new org.springframework.security.access.AccessDeniedException("Account status requires bank staff");
        locks.apply();
        Account account = accountRepository.findLockedByNumber(accountNumber)
                .orElseThrow(() -> new ResourceNotFoundException("Account not found: " + accountNumber));
        entities.refresh(account, jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);

        if (request.getStatus() == null) throw new IllegalArgumentException("Status is required");
        account.setStatus(request.getStatus());
        Account updatedAccount = accountRepository.save(account);

        audit.successAs(user, "ACCOUNT", "ACCOUNT_STATUS_CHANGED", account.getAccountNumber());
        return AccountResponseDto.fromEntity(updatedAccount);
    }

    private String generateUniqueAccountNumber() {
        String accountNumber;
        do {
            long number = 1000000000L + (long) (RANDOM.nextDouble() * 9000000000L);
            accountNumber = String.valueOf(number);
        } while (accountRepository.existsByAccountNumber(accountNumber));

        return accountNumber;
    }
}
