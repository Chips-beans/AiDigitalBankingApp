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

    Optional<Transaction> findByReferenceNumber(String referenceNumber);

    @Query("SELECT t FROM Transaction t WHERE t.sourceAccount = :account OR t.destinationAccount = :account ORDER BY t.createdAt DESC, t.id DESC")
    Page<Transaction> findAllByAccount(@Param("account") Account account, Pageable pageable);

    interface DailyAggregateProjection {
        java.sql.Date getTxDate();
        String getType();
        BigDecimal getTotalAmount();
    }

    @Query(value = """
        SELECT CAST(t.created_at AS DATE) AS txDate, 
               CAST(t.transaction_type AS VARCHAR) AS type, 
               SUM(t.amount) AS totalAmount
        FROM transactions t
        WHERE (t.source_account_id = :accountId OR t.destination_account_id = :accountId)
          AND t.created_at >= :startDate
          AND t.created_at < :endDate
          AND t.status = 'SUCCESS'
        GROUP BY CAST(t.created_at AS DATE), t.transaction_type
        ORDER BY txDate ASC
        """, nativeQuery = true)
    List<DailyAggregateProjection> findDailyAggregates(
            @Param("accountId") Long accountId,
            @Param("startDate") OffsetDateTime startDate,
            @Param("endDate") OffsetDateTime endDate
    );

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
        SELECT COALESCE(SUM(t.amount), 0)
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