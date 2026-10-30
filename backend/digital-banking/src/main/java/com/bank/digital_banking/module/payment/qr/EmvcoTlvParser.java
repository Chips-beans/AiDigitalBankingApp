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
        byte[] encoded = tlvString.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        int totalLength = encoded.length;

        while (index < totalLength) {
            if (index + 4 > totalLength) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_FORMAT", "Malformed TLV data: unexpected end of payload");
            }

            String tag = new String(encoded, index, 2, java.nio.charset.StandardCharsets.US_ASCII);
            String lengthStr = new String(encoded, index + 2, 2, java.nio.charset.StandardCharsets.US_ASCII);

            int length;
            try {
                if (!tag.matches("[0-9]{2}") || !lengthStr.matches("[0-9]{2}") || tags.containsKey(tag)) throw new NumberFormatException();
                length = Integer.parseInt(lengthStr);
            } catch (NumberFormatException e) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_FORMAT", "Malformed TLV length for tag: " + tag);
            }

            if (length < 0 || index + 4 + length > totalLength) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_FORMAT", "TLV length overflow for tag: " + tag);
            }

            String value;
            try {
                value = java.nio.charset.StandardCharsets.UTF_8.newDecoder()
                        .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                        .decode(java.nio.ByteBuffer.wrap(encoded, index + 4, length)).toString();
            } catch (java.nio.charset.CharacterCodingException invalid) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_QR_FORMAT", "Invalid UTF-8 TLV value");
            }
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
