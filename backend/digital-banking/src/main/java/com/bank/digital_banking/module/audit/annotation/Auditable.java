package com.bank.digital_banking.module.audit.annotation;

import com.bank.digital_banking.module.audit.entity.AuditSeverity;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Auditable {
    String action();
    String module();
    AuditSeverity severity() default AuditSeverity.INFO;
}