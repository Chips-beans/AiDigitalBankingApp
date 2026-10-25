package com.bank.digital_banking.module.payment.qr;

import com.bank.digital_banking.common.exception.ApiException;
import org.springframework.http.HttpStatus;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Pure Java parser for EMVCo TLV strings.
 * Safely parses top-level and nested TLV elements.
 */
public final class EmvcoTlvParser {

    private EmvcoTlvParser() {}

    /**
     * Parses a TLV string into a map of Tag -> Value.
     */
    public static Map<String, String> parse(String tlvString) {
        if (tlvString == null || tlvString.trim().isEmpty()) {
            return Collections.emptyMap();
        }

        Map<String, String> tags = new LinkedHashMap<>();
        int index = 0;
        int totalLength = tlvString.length();

        while (index < totalLength) {
            if (index + 4 > totalLength) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_FORMAT", "Malformed TLV data: unexpected end of payload");
            }

            String tag = tlvString.substring(index, index + 2);
            String lengthStr = tlvString.substring(index + 2, index + 4);

            int length;
            try {
                length = Integer.parseInt(lengthStr);
            } catch (NumberFormatException e) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_FORMAT", "Malformed TLV length for tag: " + tag);
            }

            if (length < 0 || index + 4 + length > totalLength) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_FORMAT", "TLV length overflow for tag: " + tag);
            }

            String value = tlvString.substring(index + 4, index + 4 + length);
            tags.put(tag, value);

            index += 4 + length;
        }

        return tags;
    }

    /**
     * Parses sub-tags of a nested TLV string (e.g. inside Tag 29, 30, or 62).
     */
    public static Map<String, String> parseSubTags(String subTagPayload) {
        if (subTagPayload == null || subTagPayload.isEmpty()) {
            return Collections.emptyMap();
        }
        try {
            return parse(subTagPayload);
        } catch (ApiException e) {
            return Collections.emptyMap();
        }
    }
}
