package com.bank.digital_banking.module.analytics.service.impl;

import com.bank.digital_banking.common.exception.ApiException;
import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.account.repository.AccountRepository;
import com.bank.digital_banking.module.analytics.dto.FinancialAnalyticsDTO.*;
import com.bank.digital_banking.module.analytics.service.AnalyticsService;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.transaction.repository.TransactionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;

@Service
@RequiredArgsConstructor
public class AnalyticsServiceImpl implements AnalyticsService {

    private final TransactionRepository transactionRepository;
    private final AccountRepository accountRepository;

    private Account validateAndGetAccount(User currentUser, String accountNumber) {
        Account account = accountRepository.findByAccountNumber(accountNumber)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ACCOUNT_NOT_FOUND", "Account not found: " + accountNumber));

        if (currentUser == null || currentUser.getId() == null) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "User session invalid");
        }

        // Compare primary keys safely
        if (!account.getUser().getId().equals(currentUser.getId())) {
            throw new ApiException(HttpStatus.FORBIDDEN, "ACCESS_DENIED", "You do not have permission for this action");
        }

        return account;
    }

    @Override
    @Transactional(readOnly = true)
    public List<DailyTransactionSummary> getDailyTransactionsForMonth(User currentUser, String accountNumber, int year, int month) {
        Account account = validateAndGetAccount(currentUser, accountNumber);
        Long accountId = account.getId();

        YearMonth ym = YearMonth.of(year, month);
        
        // Convert to OffsetDateTime matching Transaction entity
        OffsetDateTime start = ym.atDay(1).atStartOfDay().atOffset(ZoneOffset.UTC);
        OffsetDateTime end = ym.plusMonths(1).atDay(1).atStartOfDay().atOffset(ZoneOffset.UTC);

        var projections = transactionRepository.findDailyAggregates(accountId, start, end);

        Map<LocalDate, BigDecimal> dailyIncome = new HashMap<>();
        Map<LocalDate, BigDecimal> dailyExpense = new HashMap<>();

        if (projections != null) {
            for (var p : projections) {
                if (p.getTxDate() != null) {
                    LocalDate date = p.getTxDate().toLocalDate();
                    String typeStr = p.getType();
                    BigDecimal amount = p.getTotalAmount() != null ? p.getTotalAmount() : BigDecimal.ZERO;

                    if ("DEPOSIT".equalsIgnoreCase(typeStr)) {
                        dailyIncome.merge(date, amount, BigDecimal::add);
                    } else if ("WITHDRAWAL".equalsIgnoreCase(typeStr) || "TRANSFER".equalsIgnoreCase(typeStr)) {
                        dailyExpense.merge(date, amount, BigDecimal::add);
                    }
                }
            }
        }

        List<DailyTransactionSummary> result = new ArrayList<>();
        int daysInMonth = ym.lengthOfMonth();

        for (int day = 1; day <= daysInMonth; day++) {
            LocalDate currentDate = ym.atDay(day);
            BigDecimal income = dailyIncome.getOrDefault(currentDate, BigDecimal.ZERO);
            BigDecimal expense = dailyExpense.getOrDefault(currentDate, BigDecimal.ZERO);
            result.add(new DailyTransactionSummary(currentDate, income, expense));
        }

        return result;
    }

    @Override
    @Transactional(readOnly = true)
    public MonthlySummaryResponse getMonthlySummary(User currentUser, String accountNumber, int year, int month) {
        Account account = validateAndGetAccount(currentUser, accountNumber);
        Long accountId = account.getId();

        YearMonth ym = YearMonth.of(year, month);
        OffsetDateTime start = ym.atDay(1).atStartOfDay().atOffset(ZoneOffset.UTC);
        OffsetDateTime end = ym.plusMonths(1).atDay(1).atStartOfDay().atOffset(ZoneOffset.UTC);

        BigDecimal totalIncome = transactionRepository.sumIncomeByAccountAndDateRange(accountId, start, end);
        BigDecimal totalExpense = transactionRepository.sumExpensesByAccountAndDateRange(accountId, start, end);

        if (totalIncome == null) totalIncome = BigDecimal.ZERO;
        if (totalExpense == null) totalExpense = BigDecimal.ZERO;

        BigDecimal netSavings = totalIncome.subtract(totalExpense);

        return new MonthlySummaryResponse(ym, totalIncome, totalExpense, netSavings);
    }

    @Override
    @Transactional(readOnly = true)
    public SemesterComparisonResponse getSemesterComparison(User currentUser, String accountNumber, int year, int endMonth) {
        Account account = validateAndGetAccount(currentUser, accountNumber);
        Long accountId = account.getId();

        List<MonthlyBarChartItem> chartData = new ArrayList<>();
        BigDecimal semesterIncome = BigDecimal.ZERO;
        BigDecimal semesterExpense = BigDecimal.ZERO;

        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("MMM yyyy");

        YearMonth endYm = YearMonth.of(year, endMonth);
        YearMonth startYm = endYm.minusMonths(5);

        for (int i = 0; i < 6; i++) {
            YearMonth currentYm = startYm.plusMonths(i);
            OffsetDateTime start = currentYm.atDay(1).atStartOfDay().atOffset(ZoneOffset.UTC);
            OffsetDateTime end = currentYm.plusMonths(1).atDay(1).atStartOfDay().atOffset(ZoneOffset.UTC);

            BigDecimal income = transactionRepository.sumIncomeByAccountAndDateRange(accountId, start, end);
            BigDecimal expense = transactionRepository.sumExpensesByAccountAndDateRange(accountId, start, end);

            if (income == null) income = BigDecimal.ZERO;
            if (expense == null) expense = BigDecimal.ZERO;

            semesterIncome = semesterIncome.add(income);
            semesterExpense = semesterExpense.add(expense);

            chartData.add(new MonthlyBarChartItem(
                    currentYm.format(formatter),
                    income,
                    expense
            ));
        }

        return new SemesterComparisonResponse(chartData, semesterIncome, semesterExpense);
    }
}