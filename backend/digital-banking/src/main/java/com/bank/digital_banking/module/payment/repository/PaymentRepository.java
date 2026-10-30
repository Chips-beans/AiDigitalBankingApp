package com.bank.digital_banking.module.payment.repository;

import com.bank.digital_banking.module.payment.entity.Payment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface PaymentRepository extends JpaRepository<Payment, Long> {

    // Look up payment by MD5 / QR hash
    Optional<Payment> findByMd5Hash(String md5Hash);

    Optional<Payment> findFirstByAccountNumberAndQrTypeOrderByIdAsc(String accountNumber, String qrType);

    @org.springframework.data.jpa.repository.Lock(jakarta.persistence.LockModeType.PESSIMISTIC_WRITE)
    @org.springframework.data.jpa.repository.Query("select p from Payment p where p.md5Hash = :hash")
    Optional<Payment> findLockedByHash(@org.springframework.data.repository.query.Param("hash") String hash);

    default Optional<Payment> findByQrHash(String qrHash) {
        return findByMd5Hash(qrHash);
    }
    
}
