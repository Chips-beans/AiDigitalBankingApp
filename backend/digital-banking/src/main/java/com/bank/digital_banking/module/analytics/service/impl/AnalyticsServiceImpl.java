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
import java.math.RoundingMode;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AnalyticsServiceImpl implements AnalyticsService {
    public static final ZoneId ZONE = ZoneId.of("Asia/Phnom_Penh");
    private final TransactionRepository transactionRepository;
    private final AccountRepository accountRepository;

    private void requireUser(User user) {
        if (user == null || user.getId() == null)
            throw new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "User session invalid");
    }

    private Account validateAndGetAccount(User user, String number) {
        requireUser(user);
        Account account = accountRepository.findByAccountNumber(number).orElseThrow(() ->
                new ApiException(HttpStatus.NOT_FOUND, "ACCOUNT_NOT_FOUND", "Account not found"));
        if (!account.getUser().getId().equals(user.getId()))
            throw new ApiException(HttpStatus.FORBIDDEN, "ACCESS_DENIED", "You do not have permission for this action");
        return account;
    }

    private YearMonth period(int year, int month) {
        if (year < 1 || year > 9999 || month < 1 || month > 12)
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Invalid year or month");
        return YearMonth.of(year, month);
    }

    private OffsetDateTime start(YearMonth month) {
        return month.atDay(1).atStartOfDay(ZONE).toOffsetDateTime();
    }

    private List<DailyTransactionSummary> fill(YearMonth month,
            List<TransactionRepository.DailyAggregateProjection> rows) {
        Map<LocalDate, DailyTransactionSummary> found = new HashMap<>();
        for (var row : rows) {
            LocalDate date = row.getTxDate();
            found.put(date, new DailyTransactionSummary(date, row.getTotalIncome(), row.getTotalExpense()));
        }
        List<DailyTransactionSummary> days = new ArrayList<>();
        for (int i = 1; i <= month.lengthOfMonth(); i++) {
            LocalDate date = month.atDay(i);
            days.add(found.getOrDefault(date, new DailyTransactionSummary(date, BigDecimal.ZERO, BigDecimal.ZERO)));
        }
        return List.copyOf(days);
    }

    private BigDecimal income(List<DailyTransactionSummary> days) {
        return days.stream().map(DailyTransactionSummary::totalIncome).reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    private BigDecimal expense(List<DailyTransactionSummary> days) {
        return days.stream().map(DailyTransactionSummary::totalExpense).reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    private List<DailyTransactionSummary> accountDays(Long id, YearMonth month) {
        return fill(month, transactionRepository.findDailyAggregates(id, start(month), start(month.plusMonths(1))));
    }

    @Override
    public MonthlyOverview getMonthlyOverview(User user, int year, int month, String currency) {
        requireUser(user);
        YearMonth ym = period(year, month);
        if (currency == null || !Set.of("USD", "KHR").contains(currency))
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Currency must be USD or KHR");
        var days = fill(ym, transactionRepository.findCustomerDailyAggregates(
                user.getId(), currency, start(ym), start(ym.plusMonths(1))));
        int scale = "USD".equals(currency) ? 2 : 0;
        var daily = days.stream().map(day -> new DailyOverview(day.date(),
                money(day.totalIncome(), scale), money(day.totalExpense(), scale))).toList();
        return new MonthlyOverview(ym.toString(), currency, ZONE.getId(),
                money(income(days), scale), money(expense(days), scale), daily);
    }

    private String money(BigDecimal amount, int scale) {
        return amount.setScale(scale, RoundingMode.UNNECESSARY).toPlainString();
    }

    @Override
    public List<DailyTransactionSummary> getDailyTransactionsForMonth(User user, String number, int year, int month) {
        return accountDays(validateAndGetAccount(user, number).getId(), period(year, month));
    }

    @Override
    public MonthlySummaryResponse getMonthlySummary(User user, String number, int year, int month) {
        var days = getDailyTransactionsForMonth(user, number, year, month);
        var in = income(days);
        var out = expense(days);
        return new MonthlySummaryResponse(period(year, month), in, out, in.subtract(out));
    }

    @Override
    public SemesterComparisonResponse getSemesterComparison(User user, String number, int year, int endMonth) {
        Long id = validateAndGetAccount(user, number).getId();
        YearMonth end = period(year, endMonth);
        if (end.minusMonths(5).getYear() < 1)
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Period precedes supported calendar");
        List<MonthlyBarChartItem> items = new ArrayList<>();
        BigDecimal totalIn = BigDecimal.ZERO, totalOut = BigDecimal.ZERO;
        var labels = DateTimeFormatter.ofPattern("MMM yyyy", Locale.ENGLISH);
        for (int i = 5; i >= 0; i--) {
            YearMonth ym = end.minusMonths(i);
            var days = accountDays(id, ym);
            var in = income(days);
            var out = expense(days);
            items.add(new MonthlyBarChartItem(ym.format(labels), in, out));
            totalIn = totalIn.add(in);
            totalOut = totalOut.add(out);
        }
        return new SemesterComparisonResponse(List.copyOf(items), totalIn, totalOut);
    }
}
    