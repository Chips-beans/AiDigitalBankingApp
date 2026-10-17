package com.bank.digital_banking.module.transaction.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.Data;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

@Data
public class DepositRequestDto {

    @NotBlank(message = "Destination account number is required")
    @Pattern(regexp = "[0-9]{10,20}", message = "Account number must contain 10-20 digits")
    private String accountNumber;

    @NotNull(message = "Deposit amount is required")
    @Positive(message = "Deposit amount must be greater than zero")
    @Digits(integer = 13, fraction = 2, message = "Amount supports at most 13 integer and 2 decimal digits")
    private BigDecimal amount;

    @NotBlank(message = "Currency is required")
    @Pattern(regexp = "(?i)USD|KHR", message = "Currency must be USD or KHR")
    private String currency;

    @Size(max = 255)
    private String remark;
}