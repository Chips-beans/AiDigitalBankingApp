package com.bank.digital_banking.module.account.service;

import com.bank.digital_banking.module.account.dto.AccountResponseDto;
import com.bank.digital_banking.module.account.dto.CreateAccountRequestDto;
import com.bank.digital_banking.module.account.dto.UpdateAccountStatusDto;
import com.bank.digital_banking.module.auth.entity.User;

import java.util.List;

public interface AccountService {

    AccountResponseDto createAccount(User user, CreateAccountRequestDto request);

    List<AccountResponseDto> getUserAccounts(User user);

    AccountResponseDto getAccountByNumber(User user, String accountNumber);

    AccountResponseDto updateAccountStatus(User user, String accountNumber, UpdateAccountStatusDto request);
}