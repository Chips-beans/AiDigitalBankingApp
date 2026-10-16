package com.bank.digital_banking.module.auth.repository;

import com.bank.digital_banking.module.auth.entity.LoginAttemptLimit;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.util.Optional;

public interface LoginAttemptLimitRepository extends JpaRepository<LoginAttemptLimit, String> {
    @Modifying
    @Query(value = "insert into login_attempt_limits (id, window_started_at, attempt_count) "
            + "values (:id, CURRENT_TIMESTAMP, 0) on conflict (id) do nothing", nativeQuery = true)
    void ensureExists(@Param("id") String id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select l from LoginAttemptLimit l where l.id = :id")
    Optional<LoginAttemptLimit> findLockedById(@Param("id") String id);
}
