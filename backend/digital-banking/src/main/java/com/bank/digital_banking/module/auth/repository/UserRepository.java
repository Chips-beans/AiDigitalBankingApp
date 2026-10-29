package com.bank.digital_banking.module.auth.repository;

import com.bank.digital_banking.module.auth.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface UserRepository extends JpaRepository<User, Long> {
    @org.springframework.data.jpa.repository.Lock(jakarta.persistence.LockModeType.PESSIMISTIC_WRITE)
    @org.springframework.data.jpa.repository.Query("select u from User u where u.id = :id")
    Optional<User> findLockedById(@org.springframework.data.repository.query.Param("id") Long id);
    Optional<User> findByUsername(String username);
    Optional<User> findByTelegramSubject(String subject);
    @org.springframework.data.jpa.repository.Query("select u from User u where lower(u.email) = lower(:email)")
    Optional<User> findByEmail(@org.springframework.data.repository.query.Param("email") String email);
    Boolean existsByUsername(String username);
    @org.springframework.data.jpa.repository.Query("select (count(u) > 0) from User u where lower(u.email) = lower(:email)")
    Boolean existsByEmail(@org.springframework.data.repository.query.Param("email") String email);
}
