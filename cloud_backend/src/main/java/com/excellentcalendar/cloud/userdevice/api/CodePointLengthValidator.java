package com.excellentcalendar.cloud.userdevice.api;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * Counts Unicode code points so the limit matches JSON Schema {@code minLength/maxLength}.
 */
public class CodePointLengthValidator implements ConstraintValidator<CodePointLength, String> {

    private int min;
    private int max;

    @Override
    public void initialize(CodePointLength annotation) {
        this.min = annotation.min();
        this.max = annotation.max();
    }

    @Override
    public boolean isValid(String value, ConstraintValidatorContext context) {
        if (value == null) {
            return true;
        }
        int codePoints = value.codePointCount(0, value.length());
        return codePoints >= min && codePoints <= max;
    }
}
