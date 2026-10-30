package com.bank.digital_banking.module.account.service;

import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.transaction.entity.*;
import com.bank.digital_banking.module.transaction.repository.TransactionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.util.UUID;

/** Only called inside atomic creation of a new, still-zero account. No HTTP funding capability. */
@Service
@RequiredArgsConstructor
public class TestOpeningFundingService {
    private final OpeningFundingPolicy policy;
    private final TransactionRepository transactions;
    private final AuditTrail audit;

    @Transactional(propagation = Propagation.MANDATORY)
    public void creditNewAccount(User owner, Account account) {
        if (!policy.enabled()) return;
        if (!account.getUser().getId().equals(owner.getId()) || account.getBalance().signum() != 0
                || transactions.existsByDestinationAccountAndOperation(account, "TEST_OPENING_CREDIT")) {
            throw new IllegalStateException("Opening credit is restricted to an unfunded new owned account");
        }
        BigDecimal amount = policy.amount(account.getCurrency());
        account.setBalance(amount);
        Transaction transaction = transactions.saveAndFlush(Transaction.builder()
                .referenceNumber("TXN-" + UUID.randomUUID().toString().replace("-", ""))
                .destinationAccount(account).amount(amount).fee(BigDecimal.ZERO)
                .currency(account.getCurrency()).transactionType(TransactionType.DEPOSIT)
                .status(TransactionStatus.SUCCESS).remark("Test opening credit — non-production funds")
                .initiatedByUserId(owner.getId()).operation("TEST_OPENING_CREDIT")
                .correlationId(AuditTrail.correlation()).build());
        audit.successAs(owner, "ACCOUNT", "TEST_OPENING_CREDIT", transaction.getReferenceNumber());
    }
}
