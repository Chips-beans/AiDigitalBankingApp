package com.bank.digital_banking.module.account.dto;

import com.bank.digital_banking.module.account.entity.AccountType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import lombok.Data;

import java.math.BigDecimal;

@Data
public class CreateAccountRequestDto {

    @NotNull(message = "Account type is required")
    private AccountType accountType;

    @NotBlank(message = "Currency is required")
    @jakarta.validation.constraints.Pattern(regexp = "(?i)USD|KHR", message = "Currency must be USD or KHR")
    private String currency;

    @NotNull(message = "Initial deposit balance is required")
    @PositiveOrZero(message = "Initial deposit balance cannot be negative")
    private BigDecimal initialDeposit;
}