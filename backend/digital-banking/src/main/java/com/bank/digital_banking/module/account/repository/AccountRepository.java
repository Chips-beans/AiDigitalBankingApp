package com.bank.digital_banking.module.account.repository;

import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.auth.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

@Repository
public interface AccountRepository extends JpaRepository<Account, Long> {

    Optional<Account> findByAccountNumber(String accountNumber);

    @Query("select a.id from Account a where a.accountNumber in :numbers order by a.id")
    List<Long> findIdsByNumbers(@Param("numbers") List<String> numbers);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from Account a where a.id = :id")
    Optional<Account> findLockedById(@Param("id") Long id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from Account a where a.accountNumber = :number")
    Optional<Account> findLockedByNumber(@Param("number") String number);

    List<Account> findByUser(User user);

    List<Account> findByUser(User user, org.springframework.data.domain.Pageable pageable);

    boolean existsByAccountNumber(String accountNumber);
}
