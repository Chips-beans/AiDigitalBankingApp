package com.bank.digital_banking.module.account.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.module.account.dto.AccountResponseDto;
import com.bank.digital_banking.module.account.dto.CreateAccountRequestDto;
import com.bank.digital_banking.module.account.dto.UpdateAccountStatusDto;
import com.bank.digital_banking.module.account.service.AccountService;
import com.bank.digital_banking.module.auth.entity.User;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/accounts")
@RequiredArgsConstructor
public class AccountController {

    private final AccountService accountService;

    @PostMapping
    public ResponseEntity<ApiResponse<AccountResponseDto>> createAccount(
            @AuthenticationPrincipal User user,
            @Valid @RequestBody CreateAccountRequestDto request) {

        AccountResponseDto account = accountService.createAccount(user, request);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(account, "Account created successfully"));
    }

    @GetMapping("/me")
    public ResponseEntity<ApiResponse<List<AccountResponseDto>>> getMyAccounts(
            @AuthenticationPrincipal User user) {

        List<AccountResponseDto> accounts = accountService.getUserAccounts(user);
        return ResponseEntity.ok(ApiResponse.success(accounts, "User accounts retrieved successfully"));
    }

    @GetMapping("/{accountNumber}")
    public ResponseEntity<ApiResponse<AccountResponseDto>> getAccountByNumber(
            @AuthenticationPrincipal User user,
            @PathVariable String accountNumber) {

        AccountResponseDto account = accountService.getAccountByNumber(user, accountNumber);
        return ResponseEntity.ok(ApiResponse.success(account,"Account retrieved successfully"));
    }
    @PatchMapping("/{accountNumber}/status")
    public ResponseEntity<ApiResponse<AccountResponseDto>> updateAccountStatus(
            @AuthenticationPrincipal User user,
            @PathVariable String accountNumber,
            @Valid @RequestBody UpdateAccountStatusDto request) {

        AccountResponseDto updatedAccount = accountService.updateAccountStatus(user, accountNumber, request);
        return ResponseEntity.ok(ApiResponse.success(updatedAccount,"Account status updated successfully"));
    }
}