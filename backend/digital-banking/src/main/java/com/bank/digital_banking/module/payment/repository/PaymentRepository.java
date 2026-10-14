package com.bank.digital_banking.module.payment.repository;

import com.bank.digital_banking.module.payment.entity.Payment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface PaymentRepository extends JpaRepository<Payment, Long> {

    // Custom query method to look up payments by Bakong's generated MD5 hash
    Optional<Payment> findByMd5Hash(String md5Hash);
    
}