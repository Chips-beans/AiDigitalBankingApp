package com.bank.digital_banking.common.validation;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;
import java.lang.annotation.*;

@Documented
@Constraint(validatedBy = Utf8SizeValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
public @interface Utf8Size {
    String message() default "Must use at most {max} UTF-8 bytes";
    int max();
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
