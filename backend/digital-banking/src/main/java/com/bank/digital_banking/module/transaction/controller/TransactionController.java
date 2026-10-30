package com.bank.digital_banking.module.transaction.controller;

import com.bank.digital_banking.common.dto.ApiResponse;
import com.bank.digital_banking.common.dto.PageResponse;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.transaction.dto.DepositRequestDto;
import com.bank.digital_banking.module.transaction.dto.TransactionResponseDto;
import com.bank.digital_banking.module.transaction.dto.TransferRequestDto;
import com.bank.digital_banking.module.transaction.service.TransactionService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/transactions")
@RequiredArgsConstructor
public class TransactionController {

    private final TransactionService transactionService;

    @PostMapping("/transfer")
    public ResponseEntity<ApiResponse<TransactionResponseDto>> transfer(
            @AuthenticationPrincipal User user,
            @io.swagger.v3.oas.annotations.Parameter(required = true, description = "Stable unique key for this operation; reuse it for retries")
            @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @io.swagger.v3.oas.annotations.Parameter(description = "One-time proof from POST /auth/pin/transfer-proof; not needed to replay a completed key")
            @RequestHeader(value = "X-Pin-Proof", required = false) String pinProof,
            org.springframework.security.core.Authentication authentication,
            @Valid @RequestBody TransferRequestDto request) {

        TransactionResponseDto response = transactionService.processTransfer(user, request, key,
                new com.bank.digital_banking.module.transaction.service.FinancialCommandService.PinProof(
                        authentication.getDetails() instanceof java.util.UUID session ? session : null, pinProof));
        return ResponseEntity.ok(ApiResponse.success(response,"Transfer executed successfully" ));
    }

    @GetMapping("/quote")
    public ResponseEntity<ApiResponse<com.bank.digital_banking.module.transaction.service.ExchangeRates.Quote>> quote(
            @AuthenticationPrincipal User user,
            @RequestParam String sourceAccountNumber,
            @RequestParam String destinationAccountNumber,
            @RequestParam java.math.BigDecimal amount) {
        return ResponseEntity.ok(ApiResponse.success(
                transactionService.quote(user, sourceAccountNumber, destinationAccountNumber, amount), "Transfer quote"));
    }

    @PostMapping("/deposit")
    public ResponseEntity<ApiResponse<TransactionResponseDto>> deposit(
            @AuthenticationPrincipal User user,
            @io.swagger.v3.oas.annotations.Parameter(required = true, description = "Stable unique key for this operation; reuse it for retries")
            @RequestHeader(value = "Idempotency-Key", required = false) String key,
            @Valid @RequestBody DepositRequestDto request) {

        TransactionResponseDto response = transactionService.processDeposit(user, request, key);
        return ResponseEntity.ok(ApiResponse.success(response,"Deposit processed successfully"));
    }

    @GetMapping("/account/{accountNumber}")
    public ResponseEntity<ApiResponse<PageResponse<TransactionResponseDto>>> getAccountHistory(
            @AuthenticationPrincipal User user,
            @PathVariable String accountNumber,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size) {

        PageResponse<TransactionResponseDto> history = transactionService.getAccountTransactions(user, accountNumber, page, size);
        return ResponseEntity.ok(ApiResponse.success(history,"Transaction history retrieved successfully"));
    }

    @GetMapping("/{referenceNumber}")
    public ResponseEntity<ApiResponse<TransactionResponseDto>> getTransactionByReference(
            @AuthenticationPrincipal User user,
            @PathVariable String referenceNumber) {

        TransactionResponseDto response = transactionService.getTransactionByReference(user, referenceNumber);
        return ResponseEntity.ok(ApiResponse.success(response,"Transaction details retrieved successfully"));
    }
}
