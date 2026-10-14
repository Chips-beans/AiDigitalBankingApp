package com.bank.digital_banking.module.account.repository;

import com.bank.digital_banking.module.account.entity.Account;
import com.bank.digital_banking.module.auth.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface AccountRepository extends JpaRepository<Account, Long> {

    Optional<Account> findByAccountNumber(String accountNumber);

    List<Account> findByUser(User user);

    boolean existsByAccountNumber(String accountNumber);
}