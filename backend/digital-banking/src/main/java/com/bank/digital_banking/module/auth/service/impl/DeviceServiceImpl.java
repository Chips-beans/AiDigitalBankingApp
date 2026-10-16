package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.common.exception.AuthenticationFailedException;
import com.bank.digital_banking.module.auth.entity.*;
import com.bank.digital_banking.module.auth.repository.DeviceRepository;
import com.bank.digital_banking.module.auth.service.DeviceService;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.OffsetDateTime;

@Service @RequiredArgsConstructor
public class DeviceServiceImpl implements DeviceService {
    private final DeviceRepository devices;

    @Override @Transactional
    public Device verifyAndSaveDevice(User user, String fingerprint, String name, String type,
                                       String osName, HttpServletRequest request) {
        return bind(user, fingerprint, name, type, osName, request.getRemoteAddr());
    }

    @Override @Transactional
    public Device bind(User user, String fingerprint, String name, String type, String osName, String ip) {
        Device device = devices.findByUserAndDeviceFingerprint(user, fingerprint).orElseGet(() ->
                Device.builder().user(user).deviceFingerprint(fingerprint).status(DeviceStatus.ACTIVE).build());
        if (device.getStatus() != DeviceStatus.ACTIVE)
            throw new AuthenticationFailedException("DEVICE_REVOKED", "Device is not active for this user");
        device.setDeviceName(name);
        device.setDeviceType(type == null ? "MOBILE" : type);
        device.setOsName(osName);
        device.setIpAddress(ip);
        device.setLastLoginAt(OffsetDateTime.now());
        return devices.save(device);
    }
}
