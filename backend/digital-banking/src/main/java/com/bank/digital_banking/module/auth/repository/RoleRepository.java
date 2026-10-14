package com.bank.digital_banking.module.auth.repository;

import com.bank.digital_banking.module.auth.entity.ERole;
import com.bank.digital_banking.module.auth.entity.Role;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface RoleRepository extends JpaRepository<Role, Long> {
    Optional<Role> findByName(ERole name);
}