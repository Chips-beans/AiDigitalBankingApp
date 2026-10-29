package com.bank.digital_banking.module.analytics.service;

import com.bank.digital_banking.module.analytics.dto.FinancialAnalyticsDTO.*;
import com.bank.digital_banking.module.auth.entity.User;

import java.util.List;

public interface AnalyticsService {

    MonthlyOverview getMonthlyOverview(User currentUser, int year, int month, String currency);

    List<DailyTransactionSummary> getDailyTransactionsForMonth(User currentUser, String accountNumber, int year, int month);

    MonthlySummaryResponse getMonthlySummary(User currentUser, String accountNumber, int year, int month);

    SemesterComparisonResponse getSemesterComparison(User currentUser, String accountNumber, int year, int endMonth);
}
