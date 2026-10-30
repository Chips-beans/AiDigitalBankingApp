package com.bank.digital_banking.module.transaction.service;

import com.bank.digital_banking.common.util.TransactionLockPolicy;

import com.bank.digital_banking.common.exception.*;
import com.bank.digital_banking.common.util.CurrencyUtils;
import com.bank.digital_banking.module.account.entity.*;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.transaction.entity.*;
import com.bank.digital_banking.module.transaction.repository.TransactionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.util.*;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;

/** Shared transaction-bound primitive for local balance postings. */
@Service
@RequiredArgsConstructor
public class FinancialPostingService {
    private final AccountRepository accounts;
    private final TransactionRepository transactions;
    private final AuditTrail audit;
    private final EntityManager entities;
    private final TransactionLockPolicy locks;
    private final ExchangeRates rates;

    @Transactional(propagation = Propagation.MANDATORY)
    public Transaction post(User actor, TransactionType type, String sourceNumber, String destinationNumber,
                            BigDecimal amount, String currency, String remark) {
        if (type != TransactionType.TRANSFER && type != TransactionType.DEPOSIT)
            throw new IllegalArgumentException("Unsupported posting type");
        if (actor == null || actor.getId() == null || actor.getRoles().stream().noneMatch(role -> type == TransactionType.TRANSFER
                ? role.getName() == com.bank.digital_banking.module.auth.entity.ERole.ROLE_CUSTOMER
                : role.getName() == com.bank.digital_banking.module.auth.entity.ERole.ROLE_ADMIN
                    || role.getName() == com.bank.digital_banking.module.auth.entity.ERole.ROLE_BANK_EMPLOYEE))
            throw new org.springframework.security.access.AccessDeniedException("Operation is not permitted for this role");
        currency = CurrencyUtils.currency(currency);
        amount = CurrencyUtils.amount(amount, currency, false);
        if (type == TransactionType.TRANSFER && (sourceNumber == null || sourceNumber.equals(destinationNumber)))
            throw new IllegalArgumentException("Transfer requires different source and destination accounts");
        if (type == TransactionType.DEPOSIT && sourceNumber != null)
            throw new IllegalArgumentException("A deposit cannot debit another account");
        locks.apply();
        var numbers = sourceNumber == null ? List.of(destinationNumber) : List.of(sourceNumber, destinationNumber);
        // Scalar IDs avoid loading stale account entities before acquiring locks.
        var locked = new HashMap<String, Account>();
        for (Long id : accounts.findIdsByNumbers(numbers)) {
            Account account = accounts.findLockedById(id)
                    .orElseThrow(() -> new ResourceNotFoundException("Account not available"));
            // A locking query can still return a pre-existing first-level-cache entity.
            entities.refresh(account, LockModeType.PESSIMISTIC_WRITE);
            locked.put(account.getAccountNumber(), account);
        }
        Account destination = locked.get(destinationNumber);
        Account source = sourceNumber == null ? null : locked.get(sourceNumber);
        if (destination == null || (sourceNumber != null && (source == null || !source.getUser().getId().equals(actor.getId()))))
            throw new ResourceNotFoundException("Account not available");
        for (Account account : locked.values()) {
            if (account.getStatus() != AccountStatus.ACTIVE)
                throw new ApiException(HttpStatus.CONFLICT, "ACCOUNT_INACTIVE", "Account is not active");
        }
        // The request currency is the debited currency. Only customer transfers may credit
        // another currency, converted at the fixed rate; deposits must match exactly.
        Account debited = source != null ? source : destination;
        if (!debited.getCurrency().equals(currency)
                || (type != TransactionType.TRANSFER && !destination.getCurrency().equals(currency)))
            throw new ApiException(HttpStatus.BAD_REQUEST, "CURRENCY_MISMATCH", "Account currency does not match the request");
        var quote = rates.forDebit(amount, currency, destination.getCurrency());
        if (source != null) {
            if (source.getBalance().compareTo(amount) < 0) throw new InsufficientBalanceException("Insufficient funds");
            source.setBalance(source.getBalance().subtract(amount));
        }
        destination.setBalance(CurrencyUtils.amount(destination.getBalance().add(quote.creditAmount()),
                destination.getCurrency(), true));
        Transaction transaction = transactions.saveAndFlush(Transaction.builder()
                .referenceNumber("TXN-" + UUID.randomUUID().toString().replace("-", ""))
                .sourceAccount(source).destinationAccount(destination).amount(amount).fee(BigDecimal.ZERO)
                .currency(currency).transactionType(type).status(TransactionStatus.SUCCESS).remark(remark)
                .creditAmount(quote.converted() ? quote.creditAmount() : null)
                .creditCurrency(quote.converted() ? quote.creditCurrency() : null)
                .exchangeRate(quote.converted() ? quote.rate() : null)
                .initiatedByUserId(actor.getId()).operation(type.name()).correlationId(AuditTrail.correlation()).build());
        audit.posting(actor, type.name(), transaction.getReferenceNumber(), transaction.getCorrelationId());
        return transaction;
    }
}
