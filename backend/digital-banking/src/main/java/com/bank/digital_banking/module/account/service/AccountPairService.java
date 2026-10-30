package com.bank.digital_banking.module.account.service;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.common.util.HashUtils;
import com.bank.digital_banking.common.util.PageBounds;
import com.bank.digital_banking.common.util.TransactionLockPolicy;
import com.bank.digital_banking.module.account.dto.*;
import com.bank.digital_banking.module.account.entity.*;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.audit.service.AuditTrail;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.merchant.repository.MerchantRepository;
import com.bank.digital_banking.module.transaction.repository.TransactionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.security.SecureRandom;
import java.util.ArrayList;

@Service
@RequiredArgsConstructor
public class AccountPairService {
    private final JdbcTemplate jdbc;
    private final ObjectMapper json;
    private final AccountRepository accounts;
    private final MerchantRepository merchantRepository;
    private final TestOpeningFundingService funding;
    private final OpeningFundingPolicy policy;
    private final AuditTrail audit;
    private final TransactionLockPolicy locks;
    private final TransactionRepository transactions;
    private static final SecureRandom RANDOM = new SecureRandom();

    @Transactional
    public AccountPairDtos.Response open(User owner, String key, AccountPairDtos.Request request) {
        if (key == null || !key.matches("[A-Za-z0-9._:-]{1,128}"))
            throw new ApiException(HttpStatus.BAD_REQUEST, "IDEMPOTENCY_KEY_REQUIRED", "Provide an Idempotency-Key");
        locks.apply();
        String fingerprint = HashUtils.sha256(request.accountType().name());
        jdbc.update("INSERT INTO account_opening_requests(actor_user_id,request_key,request_hash) VALUES (?,?,?) ON CONFLICT DO NOTHING",
                owner.getId(), key, fingerprint);
        var claim = jdbc.queryForMap("SELECT request_hash,response_json FROM account_opening_requests WHERE actor_user_id=? AND request_key=? FOR UPDATE", owner.getId(), key);
        if (!fingerprint.equals(claim.get("request_hash")))
            throw new ApiException(HttpStatus.CONFLICT, "IDEMPOTENCY_CONFLICT", "Opening key belongs to a different request");
        if (claim.get("response_json") != null)
            return json.readValue((String) claim.get("response_json"), AccountPairDtos.Response.class);

        AccountCategory category = request.accountCategory() != null ? request.accountCategory() : AccountCategory.WALLET;
        var result = new ArrayList<AccountResponseDto>();
        boolean funded = policy.enabled();

        if (category == AccountCategory.WALLET) {
            // Wallets are normally provisioned at signup/profile completion; this ensures the pair exists
            // (creating and funding only what is missing) and always returns the full USD + KHR pair.
            jdbc.queryForObject("SELECT id FROM users WHERE id=? FOR UPDATE", Long.class, owner.getId());
            for (String currency : new String[]{"USD", "KHR"}) {
                Account wallet = accounts.findFirstByUserAndAccountCategoryAndCurrencyOrderByIdAsc(owner, AccountCategory.WALLET, currency)
                        .orElseGet(() -> createWallet(owner, request.accountType(), currency));
                funded &= transactions.existsByDestinationAccountAndOperation(wallet, "TEST_OPENING_CREDIT");
                result.add(AccountResponseDto.fromEntity(wallet));
            }
        } else if (category == AccountCategory.MERCHANT) {
            Long merchantId = request.merchantId();
            if (merchantId == null) {
                var m = merchantRepository.findByOwnerUserId(owner.getId(), PageBounds.ascendingId(0, 1));
                if (m.isEmpty()) throw new ApiException(HttpStatus.FORBIDDEN, "MERCHANT_REGISTRATION_REQUIRED",
                        "User must sign up for merchant app before opening merchant accounts");
                merchantId = m.get(0).getId();
            }
            long merchantCount = accounts.countByMerchantId(merchantId);
            if (merchantCount >= 2) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "ACCOUNT_LIMIT_EXCEEDED",
                        "Merchant account limit reached: merchants can have at most 2 accounts (1 USD and 1 KHR)");
            }
            for (String currency : new String[]{"USD", "KHR"}) {
                if (!accounts.existsByMerchantIdAndCurrency(merchantId, currency)) {
                    String number;
                    do { number = Long.toString(RANDOM.nextLong(1_000_000_000L, 10_000_000_000L)); }
                    while (accounts.existsByAccountNumber(number));
                    Account account = accounts.saveAndFlush(Account.builder().user(owner).accountNumber(number)
                            .accountType(request.accountType()).currency(currency).balance(BigDecimal.ZERO)
                            .status(AccountStatus.ACTIVE).accountCategory(AccountCategory.MERCHANT)
                            .merchantId(merchantId).build());
                    funding.creditNewAccount(owner, account);
                    audit.successAs(owner, "ACCOUNT", "ACCOUNT_CREATED", number);
                    result.add(AccountResponseDto.fromEntity(account));
                }
            }
        }

        var response = new AccountPairDtos.Response(result, funded);
        jdbc.update("UPDATE account_opening_requests SET response_json=? WHERE actor_user_id=? AND request_key=?",
                json.writeValueAsString(response), owner.getId(), key);
        return response;
    }

    private Account createWallet(User owner, AccountType type, String currency) {
        String number;
        do { number = Long.toString(RANDOM.nextLong(1_000_000_000L, 10_000_000_000L)); }
        while (accounts.existsByAccountNumber(number));
        Account account = accounts.saveAndFlush(Account.builder().user(owner).accountNumber(number)
                .accountType(type).currency(currency).balance(BigDecimal.ZERO)
                .status(AccountStatus.ACTIVE).accountCategory(AccountCategory.WALLET).build());
        funding.creditNewAccount(owner, account);
        audit.successAs(owner, "ACCOUNT", "ACCOUNT_CREATED", number);
        return account;
    }
}
