package com.bank.digital_banking.module.transaction.repository;

import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.transaction.entity.Transaction;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface TransactionRepository extends JpaRepository<Transaction, Long> {
    boolean existsByDestinationAccountAndOperation(com.bank.digital_banking.module.account.entity.Account account, String operation);

    Optional<Transaction> findByReferenceNumber(String referenceNumber);

    @Query("SELECT t FROM Transaction t WHERE t.sourceAccount = :account OR t.destinationAccount = :account ORDER BY t.createdAt DESC, t.id DESC")
    Page<Transaction> findAllByAccount(@Param("account") Account account, Pageable pageable);

    interface DailyAggregateProjection {
        java.time.LocalDate getTxDate();
        BigDecimal getTotalIncome();
        BigDecimal getTotalExpense();
    }

    @Query(value = """
        SELECT CAST(t.created_at AT TIME ZONE 'Asia/Phnom_Penh' AS DATE) AS txDate,
               SUM(CASE WHEN t.destination_account_id = :accountId THEN COALESCE(t.credit_amount, t.amount) ELSE 0 END) AS totalIncome,
               SUM(CASE WHEN t.source_account_id = :accountId THEN t.amount ELSE 0 END) AS totalExpense
        FROM transactions t
        WHERE (t.source_account_id = :accountId OR t.destination_account_id = :accountId)
          AND t.created_at >= :startDate
          AND t.created_at < :endDate
          AND t.status = 'SUCCESS'
        GROUP BY CAST(t.created_at AT TIME ZONE 'Asia/Phnom_Penh' AS DATE)
        ORDER BY txDate ASC
        """, nativeQuery = true)
    List<DailyAggregateProjection> findDailyAggregates(
            @Param("accountId") Long accountId,
            @Param("startDate") OffsetDateTime startDate,
            @Param("endDate") OffsetDateTime endDate
    );

    @Query(value = """
        SELECT CAST(t.created_at AT TIME ZONE 'Asia/Phnom_Penh' AS DATE) AS txDate,
               SUM(CASE WHEN dst.user_id = :userId AND COALESCE(t.credit_currency, t.currency) = :currency
                        THEN COALESCE(t.credit_amount, t.amount) ELSE 0 END) AS totalIncome,
               SUM(CASE WHEN src.user_id = :userId AND t.currency = :currency THEN t.amount ELSE 0 END) AS totalExpense
        FROM transactions t
        LEFT JOIN accounts src ON src.id = t.source_account_id
        LEFT JOIN accounts dst ON dst.id = t.destination_account_id
        WHERE (src.user_id = :userId OR dst.user_id = :userId)
          AND NOT (COALESCE(src.user_id = :userId, FALSE) AND COALESCE(dst.user_id = :userId, FALSE))
          AND (t.currency = :currency OR t.credit_currency = :currency) AND t.status = 'SUCCESS'
          AND t.created_at >= :startDate AND t.created_at < :endDate
        GROUP BY CAST(t.created_at AT TIME ZONE 'Asia/Phnom_Penh' AS DATE)
        ORDER BY txDate
        """, nativeQuery = true)
    List<DailyAggregateProjection> findCustomerDailyAggregates(
            @Param("userId") Long userId, @Param("currency") String currency,
            @Param("startDate") OffsetDateTime startDate, @Param("endDate") OffsetDateTime endDate);

    @Query("""
        SELECT COALESCE(SUM(t.amount), 0)
        FROM Transaction t
        WHERE t.sourceAccount.id = :accountId
          AND t.status = 'SUCCESS'
          AND t.createdAt >= :startDate
          AND t.createdAt < :endDate
        """)
    BigDecimal sumExpensesByAccountAndDateRange(
            @Param("accountId") Long accountId,
            @Param("startDate") OffsetDateTime startDate,
            @Param("endDate") OffsetDateTime endDate
    );

    @Query("""
        SELECT COALESCE(SUM(COALESCE(t.creditAmount, t.amount)), 0)
        FROM Transaction t
        WHERE t.destinationAccount.id = :accountId
          AND t.status = 'SUCCESS'
          AND t.createdAt >= :startDate
          AND t.createdAt < :endDate
        """)
    BigDecimal sumIncomeByAccountAndDateRange(
            @Param("accountId") Long accountId,
            @Param("startDate") OffsetDateTime startDate,
            @Param("endDate") OffsetDateTime endDate
    );
}
