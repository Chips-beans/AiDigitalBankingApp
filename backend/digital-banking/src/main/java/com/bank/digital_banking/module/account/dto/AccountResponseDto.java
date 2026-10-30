package com.bank.digital_banking.module.account.dto;

import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.account.entity.AccountCategory;
import com.bank.digital_banking.module.account.entity.AccountStatus;
import com.bank.digital_banking.module.account.entity.AccountType;
import lombok.Builder;
import lombok.Data;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Data
@Builder
@lombok.NoArgsConstructor
@lombok.AllArgsConstructor
public class AccountResponseDto {

    private Long id;
    private String accountNumber;
    private AccountType accountType;
    private String currency;
    private BigDecimal balance;
    private AccountStatus status;
    @Builder.Default
    private AccountCategory accountCategory = AccountCategory.WALLET;
    private Long merchantId;
    private OffsetDateTime createdAt;

    public static AccountResponseDto fromEntity(Account account) {
        return AccountResponseDto.builder()
                .id(account.getId())
                .accountNumber(account.getAccountNumber())
                .accountType(account.getAccountType())
                .currency(account.getCurrency())
                .balance(account.getBalance())
                .status(account.getStatus())
                .accountCategory(account.getAccountCategory() != null ? account.getAccountCategory() : AccountCategory.WALLET)
                .merchantId(account.getMerchantId())
                .createdAt(account.getCreatedAt() == null ? null : account.getCreatedAt().withOffsetSameInstant(java.time.ZoneOffset.UTC))
                .build();
    }
}
