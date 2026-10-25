package com.bank.digital_banking.module.payment.qr;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Pure Java builder for EMVCo TLV (Tag-Length-Value) formatted strings.
 * Formats data elements according to EMVCo MPM:
 *   [Tag: 2 chars][Length: 2 chars][Value: length chars]
 */
public class EmvcoTlvBuilder {

    private final Map<String, String> tags = new LinkedHashMap<>();

    public EmvcoTlvBuilder addTag(String tag, String value) {
        if (tag != null && value != null && !value.isEmpty()) {
            tags.put(tag, value);
        }
        return this;
    }

    public EmvcoTlvBuilder addTemplate(String tag, Map<String, String> subTags) {
        if (tag == null || subTags == null || subTags.isEmpty()) {
            return this;
        }

        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> entry : subTags.entrySet()) {
            String subTag = entry.getKey();
            String subValue = entry.getValue();
            if (subTag != null && subValue != null && !subValue.isEmpty()) {
                sb.append(formatTlv(subTag, subValue));
            }
        }

        if (sb.length() > 0) {
            tags.put(tag, sb.toString());
        }
        return this;
    }

    public String buildWithoutCrc() {
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> entry : tags.entrySet()) {
            sb.append(formatTlv(entry.getKey(), entry.getValue()));
        }
        return sb.toString();
    }

    /**
     * Builds the complete EMVCo QR string with Tag 63 (CRC-16) calculated and appended.
     */
    public String buildWithCrc() {
        String base = buildWithoutCrc();
        String payloadForCrc = base + EmvcoTag.CRC + "04";
        String crcValue = Crc16Ccitt.calculate(payloadForCrc);
        return payloadForCrc + crcValue;
    }

    public static String formatTlv(String tag, String value) {
        if (tag == null || tag.length() != 2) {
            throw new IllegalArgumentException("EMVCo tag must be exactly 2 characters: " + tag);
        }
        if (value == null) {
            throw new IllegalArgumentException("Value cannot be null for tag " + tag);
        }
        byte[] bytes = value.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        if (bytes.length > 99) {
            throw new IllegalArgumentException("Value length for tag " + tag + " exceeds 99 bytes: " + bytes.length);
        }
        return String.format("%s%02d%s", tag, bytes.length, value);
    }
}
