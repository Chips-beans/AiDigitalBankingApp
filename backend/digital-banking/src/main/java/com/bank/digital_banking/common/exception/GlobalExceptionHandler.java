package com.bank.digital_banking.common.exception;

import com.bank.digital_banking.common.dto.ApiErrorResponse;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.*;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import java.util.*;

@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(org.springframework.web.multipart.MaxUploadSizeExceededException.class)
    public ResponseEntity<ApiErrorResponse> photoTooLarge(Exception ex, HttpServletRequest r) {
        if (r.getRequestURI().startsWith("/api/v1/merchants/me/"))
            return error(413, "MERCHANT_LOGO_TOO_LARGE", "Choose a JPG or PNG logo up to 5 MB", r);
        return error(413, "PROFILE_PHOTO_TOO_LARGE", "Choose a JPG or PNG up to 5 MB", r);
    }
    @ExceptionHandler(org.springframework.web.multipart.support.MissingServletRequestPartException.class)
    public ResponseEntity<ApiErrorResponse> missingPart(Exception ex, HttpServletRequest r) {
        return error(400, "INVALID_REQUEST", r.getRequestURI().startsWith("/api/v1/merchants/me/")
                ? "Choose a shop logo" : "Choose a profile photo", r);
    }
    @ExceptionHandler(org.springframework.web.bind.MissingRequestHeaderException.class)
    public ResponseEntity<ApiErrorResponse> missingHeader(org.springframework.web.bind.MissingRequestHeaderException ex, HttpServletRequest r) {
        return error(400, "Idempotency-Key".equalsIgnoreCase(ex.getHeaderName()) ? "IDEMPOTENCY_KEY_REQUIRED" : "INVALID_REQUEST",
                "A required request header is missing", r);
    }
    @ExceptionHandler(org.springframework.jdbc.UncategorizedSQLException.class)
    public ResponseEntity<ApiErrorResponse> jdbcFailure(org.springframework.jdbc.UncategorizedSQLException ex, HttpServletRequest r) {
        // JdbcTemplate does not classify PostgreSQL 55P03 consistently with Hibernate.
        String state = ex.getSQLException().getSQLState();
        if (Set.of("55P03", "40P01", "40001").contains(state == null ? "" : state)) return busy(ex, r);
        return unexpected(ex, r);
    }
    @ExceptionHandler(AuditUnavailableException.class)
    public ResponseEntity<ApiErrorResponse> auditUnavailable(Exception ex, HttpServletRequest r) {
        return error(503, "AUDIT_UNAVAILABLE", "Required audit storage is unavailable; try again later", r);
    }
    @ExceptionHandler(org.springframework.dao.PessimisticLockingFailureException.class)
    public ResponseEntity<ApiErrorResponse> busy(Exception ex, HttpServletRequest r) {
        return error(409, "CONCURRENT_UPDATE", "Another request is changing this resource; try again", r);
    }
    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiErrorResponse> api(ApiException ex, HttpServletRequest request) {
        var builder = ResponseEntity.status(ex.getStatus());
        if (ex.getRetryAfterSeconds() != null) builder.header(HttpHeaders.RETRY_AFTER, ex.getRetryAfterSeconds().toString());
        return builder.body(ApiErrorResponse.of(ex.getStatus().value(), ex.getCode(), ex.getMessage(), request.getRequestURI(), Map.of(), ex.getRetryAfterSeconds()));
    }
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiErrorResponse> invalid(MethodArgumentNotValidException ex, HttpServletRequest request) {
        Map<String,String> fields = new LinkedHashMap<>();
        ex.getBindingResult().getFieldErrors().forEach(e -> fields.putIfAbsent(e.getField(), e.getDefaultMessage()));
        return ResponseEntity.badRequest().body(ApiErrorResponse.of(400, "VALIDATION_FAILED", "Check the submitted fields", request.getRequestURI(), fields, null));
    }
    @ExceptionHandler({IllegalArgumentException.class, HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class})
    public ResponseEntity<ApiErrorResponse> badRequest(Exception ex, HttpServletRequest r) {
        return error(400, "INVALID_REQUEST", "Request contains invalid values", r);
    }
    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ApiErrorResponse> missing(Exception ex, HttpServletRequest r) { return error(404, "RESOURCE_NOT_FOUND", "Resource is not available", r); }
    @ExceptionHandler(InsufficientBalanceException.class)
    public ResponseEntity<ApiErrorResponse> funds(Exception ex, HttpServletRequest r) { return error(400, "INSUFFICIENT_FUNDS", "Insufficient account balance", r); }
    @ExceptionHandler(BadCredentialsException.class)
    public ResponseEntity<ApiErrorResponse> auth(Exception ex, HttpServletRequest r) { return error(401, "AUTHENTICATION_FAILED", "Invalid credentials", r); }
    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ApiErrorResponse> denied(Exception ex, HttpServletRequest r) { return error(403, "ACCESS_DENIED", "You do not have permission for this action", r); }
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ApiErrorResponse> conflict(Exception ex, HttpServletRequest r) { return error(409, "RESOURCE_CONFLICT", "The request conflicts with an existing resource", r); }
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiErrorResponse> unexpected(Exception ex, HttpServletRequest r) {
        if (ex instanceof org.springframework.web.ErrorResponse mvcError
                && mvcError.getStatusCode().is4xxClientError()) {
            int status = mvcError.getStatusCode().value();
            String code = switch (status) {
                case 404 -> "RESOURCE_NOT_FOUND";
                case 405 -> "METHOD_NOT_ALLOWED";
                case 406 -> "NOT_ACCEPTABLE";
                case 415 -> "UNSUPPORTED_MEDIA_TYPE";
                default -> "INVALID_REQUEST";
            };
            return ResponseEntity.status(status).headers(mvcError.getHeaders()).body(ApiErrorResponse.of(
                    status, code, "Request does not match this endpoint", r.getRequestURI(), Map.of(), null));
        }
        org.slf4j.LoggerFactory.getLogger(getClass()).error("Request failed: {}", ex.getClass().getSimpleName());
        return error(500, "INTERNAL_ERROR", "The request could not be completed", r);
    }
    private ResponseEntity<ApiErrorResponse> error(int status, String code, String message, HttpServletRequest r) {
        return ResponseEntity.status(status).body(ApiErrorResponse.of(status, code, message, r.getRequestURI(), Map.of(), null));
    }
}
