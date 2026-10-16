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
        org.slf4j.LoggerFactory.getLogger(getClass()).error("Request failed: {}", ex.getClass().getSimpleName());
        return error(500, "INTERNAL_ERROR", "The request could not be completed", r);
    }
    private ResponseEntity<ApiErrorResponse> error(int status, String code, String message, HttpServletRequest r) {
        return ResponseEntity.status(status).body(ApiErrorResponse.of(status, code, message, r.getRequestURI(), Map.of(), null));
    }
}
