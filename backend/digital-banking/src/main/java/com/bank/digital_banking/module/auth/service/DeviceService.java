package com.bank.digital_banking.module.auth.service;

import com.bank.digital_banking.module.auth.entity.Device;
import com.bank.digital_banking.module.auth.entity.User;
import jakarta.servlet.http.HttpServletRequest;

public interface DeviceService {
    Device bind(User user, String fingerprint, String name, String type, String osName, String ip);

    Device verifyAndSaveDevice(User user, String fingerprint, String deviceName, String deviceType, String osName, HttpServletRequest request);
}