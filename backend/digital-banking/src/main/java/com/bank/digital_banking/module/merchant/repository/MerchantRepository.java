package com.bank.digital_banking.module.merchant.repository;

import com.bank.digital_banking.module.merchant.entity.Merchant;
import com.bank.digital_banking.module.merchant.entity.MerchantStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface MerchantRepository extends JpaRepository<Merchant, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select m from Merchant m where m.id = :id")
    Optional<Merchant> findLockedById(@Param("id") Long id);

    Optional<Merchant> findByMerchantId(String merchantId);

    Optional<Merchant> findByBakongAccountId(String bakongAccountId);

    List<Merchant> findByOwnerUserId(Long ownerUserId);

    List<Merchant> findByStatus(MerchantStatus status);

    boolean existsByBakongAccountId(String bakongAccountId);
}
