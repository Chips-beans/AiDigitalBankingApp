package com.bank.digital_banking.module.auth.repository;

import com.bank.digital_banking.module.auth.entity.OtpRateLimit;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.util.Optional;

public interface OtpRateLimitRepository extends JpaRepository<OtpRateLimit, String> {
    @Modifying
    @Query(value = "insert into otp_rate_limits (id, window_started_at, request_count) values (:id, CURRENT_TIMESTAMP, 0) on conflict (id) do nothing", nativeQuery = true)
    void ensureExists(@Param("id") String id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from OtpRateLimit r where r.id = :id")
    Optional<OtpRateLimit> findLockedById(@Param("id") String id);
}
