package com.bank.digital_banking.common.exception;

public class AuthenticationFailedException extends ApiException {
    public AuthenticationFailedException(String message) {
        this("AUTHENTICATION_FAILED", message);
    }
    public AuthenticationFailedException(String code, String message) {
        super(org.springframework.http.HttpStatus.UNAUTHORIZED, code, message);
    }
}
