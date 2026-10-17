package com.bank.digital_banking.common.exception;

/** Audit storage is required for financial writes; expose only a generic API error. */
public class AuditUnavailableException extends RuntimeException {
    public AuditUnavailableException(Throwable cause) {
        super("Required audit storage is unavailable", cause);
    }
}
