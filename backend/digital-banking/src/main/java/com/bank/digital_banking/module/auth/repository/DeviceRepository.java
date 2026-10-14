package com.bank.digital_banking.module.auth.repository;

import com.bank.digital_banking.module.auth.entity.Device;
import com.bank.digital_banking.module.auth.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface DeviceRepository extends JpaRepository<Device, Long> {

    Optional<Device> findByDeviceFingerprint(String deviceFingerprint);

    Optional<Device> findByUserAndDeviceFingerprint(User user, String deviceFingerprint);

    List<Device> findByUser(User user);
}