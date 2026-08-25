package com.excellentcalendar.cloud.userdevice.api;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;
import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Validates a string's length in Unicode code points (JSON Schema {@code minLength/maxLength}
 * semantics) instead of Bean Validation's UTF-16 {@code @Size}. Surrogate pairs (emoji, CJK
 * extension characters) count once, matching the wire contract.
 */
@Documented
@Constraint(validatedBy = CodePointLengthValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface CodePointLength {

    String message() default "length must be between {min} and {max} Unicode code points";

    int min() default 0;

    int max() default Integer.MAX_VALUE;

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
