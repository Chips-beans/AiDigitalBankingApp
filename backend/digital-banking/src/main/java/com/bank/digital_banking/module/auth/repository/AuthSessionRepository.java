package com.bank.digital_banking.module.auth.repository;

import com.bank.digital_banking.module.auth.entity.AuthSession;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

public interface AuthSessionRepository extends JpaRepository<AuthSession, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from AuthSession s where s.id = :id")
    Optional<AuthSession> findLockedById(@Param("id") UUID id);

    @Modifying
    @Query("update AuthSession s set s.revokedAt = :now where s.user.id = :userId and s.device.id = :deviceId and s.revokedAt is null")
    int revokeForDevice(@Param("userId") Long userId, @Param("deviceId") Long deviceId,
                        @Param("now") OffsetDateTime now);
}
