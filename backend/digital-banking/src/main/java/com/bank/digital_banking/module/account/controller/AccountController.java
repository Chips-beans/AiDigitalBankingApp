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
    private final com.bank.digital_banking.module.account.service.AccountPairService pairs;
    private final com.bank.digital_banking.module.account.service.OpeningFundingPolicy openingPolicy;

    @GetMapping("/opening-policy")
    public ResponseEntity<ApiResponse<com.bank.digital_banking.module.account.dto.AccountPairDtos.Policy>> openingPolicy() {
        return ResponseEntity.ok(ApiResponse.success(openingPolicy.response(), "Account opening policy"));
    }

    @PostMapping("/pairs")
    public ResponseEntity<ApiResponse<com.bank.digital_banking.module.account.dto.AccountPairDtos.Response>> openPair(
            @AuthenticationPrincipal User user,
            @io.swagger.v3.oas.annotations.Parameter(required = true, description = "Required immutable account-pair opening key")
            @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @Valid @RequestBody com.bank.digital_banking.module.account.dto.AccountPairDtos.Request request) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(pairs.open(user, key, request), "Accounts opened successfully"));
    }

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
            @AuthenticationPrincipal User user, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "20") int size) {

        List<AccountResponseDto> accounts = accountService.getUserAccounts(user, page, size);
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
