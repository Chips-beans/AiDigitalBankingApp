package com.bank.digital_banking.module.fraud.adapter;

import org.springframework.stereotype.Component;

@Component
public class GeoLocationAdapter {

    public boolean isHighRiskIp(String ipAddress) {
        if (ipAddress == null || ipAddress.isBlank()) {
            return false;
        }
        // Example logic: Flag local/internal proxies or test ranges if needed
        return ipAddress.startsWith("10.99.") || ipAddress.startsWith("192.168.99.");
    }
}