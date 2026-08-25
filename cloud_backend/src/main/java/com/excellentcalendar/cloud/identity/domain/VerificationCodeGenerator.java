package com.excellentcalendar.cloud.identity.domain;

/**
 * Port for generating the 6-digit verification code.
 */
@FunctionalInterface
public interface VerificationCodeGenerator {

    String generate();
}
