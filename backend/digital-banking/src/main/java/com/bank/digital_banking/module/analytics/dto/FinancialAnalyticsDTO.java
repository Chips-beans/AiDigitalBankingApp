package com.bank.digital_banking.module.analytics.dto;


import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;

public class FinancialAnalyticsDTO {

    public record DailyOverview(LocalDate date, String totalIncome, String totalExpense) {}

    public record MonthlyOverview(String month, String currency, String timeZone,
                                  String totalIncome, String totalExpense, List<DailyOverview> daily) {}

    // 1. Daily breakdown entry
    public record DailyTransactionSummary(
            LocalDate date,
            BigDecimal totalIncome,
            BigDecimal totalExpense
    ) {}

    // 2 & 3. Monthly Financial Summary
    public record MonthlySummaryResponse(
            YearMonth month,
            BigDecimal totalIncome,
            BigDecimal totalExpense,
            BigDecimal netSavings
    ) {}

    // Item for the 6-month bar chart comparison
    public record MonthlyBarChartItem(
            String monthLabel, // e.g., "Jan 2026", "Feb 2026"
            BigDecimal totalIncome,
            BigDecimal totalExpense
    ) {}

    // 4. Semester (6-Month) Comparison Response
    public record SemesterComparisonResponse(
            List<MonthlyBarChartItem> monthlyData,
            BigDecimal semesterTotalIncome,
            BigDecimal semesterTotalExpense
    ) {}
}
