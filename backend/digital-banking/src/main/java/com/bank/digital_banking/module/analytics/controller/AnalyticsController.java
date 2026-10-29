package com.bank.digital_banking.module.analytics.controller;

import com.bank.digital_banking.module.analytics.dto.FinancialAnalyticsDTO.*;
import com.bank.digital_banking.module.analytics.service.AnalyticsService;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.common.dto.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/analytics")
@RequiredArgsConstructor
@Tag(name = "Analytics", description = "Financial analytics and reporting endpoints")
public class AnalyticsController {

    private final AnalyticsService analyticsService;

    @GetMapping("/monthly-overview")
    @Operation(summary = "Customer-wide monthly cash flow by currency; excludes transfers between own accounts")
    public ResponseEntity<ApiResponse<MonthlyOverview>> getMonthlyOverview(
            @AuthenticationPrincipal User currentUser, @RequestParam int year,
            @RequestParam int month, @RequestParam String currency) {
        return ResponseEntity.ok(ApiResponse.success(
                analyticsService.getMonthlyOverview(currentUser, year, month, currency), "Monthly analytics"));
    }

    @GetMapping("/daily")
    @Operation(summary = "Fetch daily transaction totals (Income & Expense) for every day in a month")
    public ResponseEntity<List<DailyTransactionSummary>> getDailySummary(
            @AuthenticationPrincipal User currentUser,
            @RequestParam String accountNumber,
            @RequestParam int year,
            @RequestParam int month) {
        return ResponseEntity.ok(analyticsService.getDailyTransactionsForMonth(currentUser, accountNumber, year, month));
    }

    @GetMapping("/monthly-summary")
    @Operation(summary = "Fetch total spending and total income for a specific month")
    public ResponseEntity<MonthlySummaryResponse> getMonthlySummary(
            @AuthenticationPrincipal User currentUser,
            @RequestParam String accountNumber,
            @RequestParam int year,
            @RequestParam int month) {
        return ResponseEntity.ok(analyticsService.getMonthlySummary(currentUser, accountNumber, year, month));
    }

    @GetMapping("/semester-comparison")
    @Operation(summary = "Fetch 6-month semester comparison data (Income vs Expense) for bar chart rendering")
    public ResponseEntity<SemesterComparisonResponse> getSemesterComparison(
            @AuthenticationPrincipal User currentUser,
            @RequestParam String accountNumber,
            @RequestParam int year,
            @RequestParam int endMonth) {
        return ResponseEntity.ok(analyticsService.getSemesterComparison(currentUser, accountNumber, year, endMonth));
    }
}
