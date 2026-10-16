package com.bank.digital_banking.common.dto;

import java.time.OffsetDateTime;
import java.util.Map;

public record ApiErrorResponse(boolean success, String error, String message, int status,
                               String path, OffsetDateTime timestamp,
                               Map<String, String> fieldErrors, Long retryAfterSeconds) {
    public static ApiErrorResponse of(int status, String code, String message, String path,
                                      Map<String, String> fields, Long retryAfter) {
        return new ApiErrorResponse(false, code, message, status, path,
                OffsetDateTime.now(), fields, retryAfter);
    }
}
