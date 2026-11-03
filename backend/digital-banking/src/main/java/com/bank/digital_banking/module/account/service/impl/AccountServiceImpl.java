package com.bank.digital_banking.module.account.service.impl;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.exception.ResourceNotFoundException;
import com.bank.digital_banking.common.util.CurrencyUtils;
import com.bank.digital_banking.common.util.PageBounds;
import com.bank.digital_banking.common.util.TransactionLockPolicy;
import com.bank.digital_banking.module.account.dto.AccountResponseDto;
import com.bank.digital_banking.module.account.dto.CreateAccountRequestDto;
import com.bank.digital_banking.module.account.dto.UpdateAccountStatusDto;
import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.account.entity.AccountCategory;
import com.bank.digital_banking.module.account.entity.AccountStatus;
import com.bank.digital_banking.module.account.entity.AccountType;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.account.service.AccountService;
import com.bank.digital_banking.module.account.service.TestOpeningFundingService;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.ERole;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.merchant.entity.Merchant;
import com.bank.digital_banking.module.merchant.repository.MerchantRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
public class AccountServiceImpl implements AccountService {

    private final AccountRepository accountRepository;
    private final MerchantRepository merchantRepository;
    private final TestOpeningFundingService funding;
    private final AuditTrail audit;
    private final jakarta.persistence.EntityManager entities;
    private final TransactionLockPolicy locks;
    private static final SecureRandom RANDOM = new SecureRandom();

    @Override
    @Transactional
    public AccountResponseDto createAccount(User user, CreateAccountRequestDto request) {
        String currency = CurrencyUtils.currency(request.getCurrency());
        CurrencyUtils.amount(request.getInitialDeposit(), currency, true);
        if (request.getInitialDeposit().signum() != 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "VERIFIED_FUNDING_REQUIRED", "New accounts must start at zero; use a verified funding process");
        }

        AccountCategory category = request.getAccountCategory() != null ? request.getAccountCategory() : AccountCategory.WALLET;

        Long merchantId = null;
        if (category == AccountCategory.WALLET) {
            long walletCount = accountRepository.countByUserAndAccountCategory(user, AccountCategory.WALLET);
            if (walletCount >= 2) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "ACCOUNT_LIMIT_EXCEEDED",
                        "User wallet limit reached: each user can have at most 2 wallet accounts (1 USD and 1 KHR)");
            }
            if (accountRepository.existsByUserAndAccountCategoryAndCurrency(user, AccountCategory.WALLET, currency)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "ACCOUNT_LIMIT_EXCEEDED",
                        "User already has a " + currency + " wallet account");
            }
        } else if (category == AccountCategory.MERCHANT) {
            merchantId = request.getMerchantId();
            Merchant merchant = null;
            if (merchantId != null) {
                merchant = merchantRepository.findById(merchantId)
                        .orElseThrow(() -> new ResourceNotFoundException("Merchant not found: " + request.getMerchantId()));
            } else {
                List<Merchant> userMerchants = merchantRepository.findByOwnerUserId(user.getId(), PageBounds.ascendingId(0, 1));
                if (!userMerchants.isEmpty()) {
                    merchant = userMerchants.get(0);
                    merchantId = merchant.getId();
                }
            }
            if (merchant == null || (!merchant.getOwnerUserId().equals(user.getId()) && !isAdmin(user))) {
                throw new ApiException(HttpStatus.FORBIDDEN, "MERCHANT_REGISTRATION_REQUIRED",
                        "User must sign up for merchant app before opening merchant accounts");
            }
            long merchantCount = accountRepository.countByMerchantId(merchantId);
            if (merchantCount >= 2) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "ACCOUNT_LIMIT_EXCEEDED",
                        "Merchant account limit reached: merchants can have at most 2 accounts (1 USD and 1 KHR)");
            }
            if (accountRepository.existsByMerchantIdAndCurrency(merchantId, currency)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "ACCOUNT_LIMIT_EXCEEDED",
                        "Merchant already has a " + currency + " account");
            }
        }

        String accountNumber = generateUniqueAccountNumber();

        Account account = Account.builder()
                .user(user)
                .accountNumber(accountNumber)
                .accountType(request.getAccountType())
                .currency(currency)
                .balance(request.getInitialDeposit())
                .status(AccountStatus.ACTIVE)
                .accountCategory(category)
                .merchantId(merchantId)
                .build();

        Account savedAccount = accountRepository.save(account);
        audit.successAs(user, "ACCOUNT", "ACCOUNT_CREATED", savedAccount.getAccountNumber());
        return AccountResponseDto.fromEntity(savedAccount);
    }

    @Override
    @Transactional(readOnly = true)
    public List<AccountResponseDto> getUserAccounts(User user, int page, int size) {
        return accountRepository.findByUserAndAccountCategory(user, AccountCategory.WALLET, PageBounds.ascendingId(page, size))
                .stream()
                .map(AccountResponseDto::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<AccountResponseDto> getUserMerchantAccounts(User user, int page, int size) {
        return accountRepository.findByUserAndAccountCategory(user, AccountCategory.MERCHANT, PageBounds.ascendingId(page, size))
                .stream()
                .map(AccountResponseDto::fromEntity)
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<AccountResponseDto> getAllUserAccounts(User user, int page, int size) {
        return accountRepository.findByUser(user, PageBounds.ascendingId(page, size))
                .stream()
                .map(AccountResponseDto::fromEntity)
                .toList();
    }

    @Override
    @Transactional
    public List<AccountResponseDto> createDefaultUserWallets(User user) {
        List<AccountResponseDto> created = new ArrayList<>();
        for (String currency : new String[]{"USD", "KHR"}) {
            if (!accountRepository.existsByUserAndAccountCategoryAndCurrency(user, AccountCategory.WALLET, currency)) {
                String number = generateUniqueAccountNumber();
                Account account = accountRepository.saveAndFlush(Account.builder()
                        .user(user)
                        .accountNumber(number)
                        .accountType(AccountType.SAVINGS)
                        .currency(currency)
                        .balance(BigDecimal.ZERO)
                        .status(AccountStatus.ACTIVE)
                        .accountCategory(AccountCategory.WALLET)
                        .merchantId(null)
                        .build());
                funding.creditNewAccount(user, account);
                audit.successAs(user, "ACCOUNT", "WALLET_ACCOUNT_CREATED", number);
                created.add(AccountResponseDto.fromEntity(account));
            }
        }
        return created;
    }

    @Override
    @Transactional
    public List<AccountResponseDto> createDefaultMerchantAccounts(User owner, Merchant merchant) {
        List<AccountResponseDto> created = new ArrayList<>();
        for (String currency : new String[]{"USD", "KHR"}) {
            if (!accountRepository.existsByMerchantIdAndCurrency(merchant.getId(), currency)) {
                String number = generateUniqueAccountNumber();
                Account account = accountRepository.saveAndFlush(Account.builder()
                        .user(owner)
                        .accountNumber(number)
                        .accountType(AccountType.CHECKING)
                        .currency(currency)
                        .balance(BigDecimal.ZERO)
                        .status(AccountStatus.ACTIVE)
                        .accountCategory(AccountCategory.MERCHANT)
                        .merchantId(merchant.getId())
                        .build());
                funding.creditNewAccount(owner, account);
                audit.successAs(owner, "ACCOUNT", "MERCHANT_ACCOUNT_CREATED", number);
                created.add(AccountResponseDto.fromEntity(account));
            }
        }
        return created;
    }

    @Override
    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.MANDATORY)
    public List<AccountResponseDto> openMerchantWallets(User owner, long merchantId) {
        // Self-service shops open KHR then USD at zero. Merchant wallets never receive
        // the customer development opening credit; the database index prevents duplicates.
        List<AccountResponseDto> created = new ArrayList<>();
        for (String currency : new String[]{"KHR", "USD"}) {
            String number = generateUniqueAccountNumber();
            Account account = accountRepository.saveAndFlush(Account.builder()
                    .user(owner)
                    .accountNumber(number)
                    .accountType(AccountType.CHECKING)
                    .currency(currency)
                    .balance(BigDecimal.ZERO)
                    .status(AccountStatus.ACTIVE)
                    .accountCategory(AccountCategory.MERCHANT)
                    .merchantId(merchantId)
                    .build());
            audit.successAs(owner, "ACCOUNT", "MERCHANT_ACCOUNT_CREATED", number);
            created.add(AccountResponseDto.fromEntity(account));
        }
        return created;
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
                role.getName() == ERole.ROLE_ADMIN
                        || role.getName() == ERole.ROLE_BANK_EMPLOYEE);
        if (!staff) throw new AccessDeniedException("Account status requires bank staff");
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

    private boolean isAdmin(User user) {
        return user.getRoles().stream().anyMatch(role -> role.getName() == ERole.ROLE_ADMIN);
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
