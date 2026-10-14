package com.bank.digital_banking.module.account.dto;

import com.bank.digital_banking.module.account.entity.AccountStatus;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class UpdateAccountStatusDto {

    @NotNull(message = "Account status is required")
    private AccountStatus status;
}