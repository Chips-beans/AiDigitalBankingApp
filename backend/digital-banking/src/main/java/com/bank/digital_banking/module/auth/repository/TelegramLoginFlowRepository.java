package com.bank.digital_banking.module.auth.repository;

import com.bank.digital_banking.module.auth.entity.TelegramLoginFlow;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.time.OffsetDateTime;
import java.util.Optional;

public interface TelegramLoginFlowRepository extends JpaRepository<TelegramLoginFlow, String> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select f from TelegramLoginFlow f where f.id = :id")
    Optional<TelegramLoginFlow> findLockedById(@Param("id") String id);
    @Modifying @Query("delete from TelegramLoginFlow f where f.expiresAt < :now")
    int deleteExpired(@Param("now") OffsetDateTime now);
}
