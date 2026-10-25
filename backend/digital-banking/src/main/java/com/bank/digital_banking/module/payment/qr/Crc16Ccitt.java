package com.bank.digital_banking.module.payment.qr;

import java.nio.charset.StandardCharsets;

/**
 * Pure Java implementation of CRC-16/CCITT-FALSE according to ISO/IEC 13239 and EMVCo QR specifications.
 * Polynomial: 0x1021 (x^16 + x^12 + x^5 + 1)
 * Initial Value: 0xFFFF
 * Input Reflected: false
 * Result Reflected: false
 * Final XOR: 0x0000
 */
public final class Crc16Ccitt {

    private static final int POLYNOMIAL = 0x1021;
    private static final int INITIAL_VALUE = 0xFFFF;

    private Crc16Ccitt() {}

    /**
     * Calculates the 16-bit CRC over the given string payload (using UTF-8 bytes)
     * and returns it as a 4-character uppercase hexadecimal string.
     */
    public static String calculate(String payload) {
        if (payload == null) {
            throw new IllegalArgumentException("Payload cannot be null for CRC calculation");
        }
        byte[] bytes = payload.getBytes(StandardCharsets.UTF_8);
        int crc = INITIAL_VALUE;

        for (byte b : bytes) {
            crc ^= (b & 0xFF) << 8;
            for (int i = 0; i < 8; i++) {
                if ((crc & 0x8000) != 0) {
                    crc = ((crc << 1) ^ POLYNOMIAL) & 0xFFFF;
                } else {
                    crc = (crc << 1) & 0xFFFF;
                }
            }
        }

        return String.format("%04X", crc);
    }

    /**
     * Verifies whether the full EMVCo QR string has a valid CRC matching Tag 63.
     * In EMVCo QR strings, Tag 63 is the last tag formatted as "6304XXXX".
     */
    public static boolean verify(String fullPayload) {
        if (fullPayload == null || fullPayload.length() < 8) {
            return false;
        }

        int crcTagIndex = fullPayload.lastIndexOf("6304");
        if (crcTagIndex < 0 || crcTagIndex + 8 != fullPayload.length()) {
            return false;
        }

        // The CRC in EMVCo is computed over all characters preceding the 4 hex digits,
        // including the "6304" tag and length indicator.
        String payloadToHash = fullPayload.substring(0, crcTagIndex + 4);
        String expectedCrc = fullPayload.substring(crcTagIndex + 4);

        String calculatedCrc = calculate(payloadToHash);
        return calculatedCrc.equalsIgnoreCase(expectedCrc);
    }
}
