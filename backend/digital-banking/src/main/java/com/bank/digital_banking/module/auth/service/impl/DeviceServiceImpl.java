package com.bank.digital_banking.module.auth.service.impl;

import com.bank.digital_banking.module.auth.entity.Device;
import com.bank.digital_banking.module.auth.entity.DeviceStatus;
import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.auth.repository.DeviceRepository;
import com.bank.digital_banking.module.auth.service.DeviceService;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class DeviceServiceImpl implements DeviceService {

    private final DeviceRepository deviceRepository;

    @Override
    @Transactional
    public Device verifyAndSaveDevice(User user, String fingerprint, String deviceName, String deviceType, String osName, HttpServletRequest request) {
        String ipAddress = extractClientIp(request);

        Optional<Device> existingDevice = deviceRepository.findByDeviceFingerprint(fingerprint);

        if (existingDevice.isPresent()) {
            Device device = existingDevice.get();
            device.setUser(user); // Transfer/associate device with logging-in user
            device.setLastLoginAt(OffsetDateTime.now());
            device.setIpAddress(ipAddress);
            if (deviceName != null) device.setDeviceName(deviceName);
            if (deviceType != null) device.setDeviceType(deviceType);
            if (osName != null) device.setOsName(osName);
            return deviceRepository.save(device);
        } else {
            Device newDevice = Device.builder()
                    .user(user)
                    .deviceFingerprint(fingerprint)
                    .deviceName(deviceName != null ? deviceName : "Unknown Device")
                    .deviceType(deviceType != null ? deviceType : "MOBILE")
                    .osName(osName)
                    .ipAddress(ipAddress)
                    .status(DeviceStatus.ACTIVE)
                    .build();

            return deviceRepository.save(newDevice);
        }
    }

    private String extractClientIp(HttpServletRequest request) {
        String xForwardedFor = request.getHeader("X-Forwarded-For");
        if (xForwardedFor != null && !xForwardedFor.isEmpty() && !"unknown".equalsIgnoreCase(xForwardedFor)) {
            return xForwardedFor.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}