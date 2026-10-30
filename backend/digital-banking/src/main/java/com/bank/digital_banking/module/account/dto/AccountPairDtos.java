package com.bank.digital_banking.module.account.dto;

import com.bank.digital_banking.module.account.entity.AccountCategory;
import com.bank.digital_banking.module.account.entity.AccountType;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.util.List;

public final class AccountPairDtos {
    private AccountPairDtos() {}
    public record Request(
            @NotNull AccountType accountType,
            AccountCategory accountCategory,
            Long merchantId
    ) {
        public Request(AccountType accountType) {
            this(accountType, AccountCategory.WALLET, null);
        }
    }
    public record Policy(boolean testFundingEnabled, BigDecimal usdOpeningBalance, BigDecimal khrOpeningBalance) {}
    public record Response(List<AccountResponseDto> accounts, boolean testFundingApplied) {}
}
