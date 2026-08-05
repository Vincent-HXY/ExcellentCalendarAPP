package com.excellentcalendar.cloud.identity.service;

/**
 * Domain exceptions for the identity module.
 * Each inner class maps to a specific business error that the controller
 * translates into the appropriate HTTP status and error code.
 */
public abstract class IdentityException extends RuntimeException {

    protected IdentityException(String message) {
        super(message);
    }

    // -- Authentication --

    public static class InvalidCredentials extends IdentityException {
        public InvalidCredentials(String message) {
            super(message);
        }
    }

    public static class AccountDisabled extends IdentityException {
        public AccountDisabled(String message) {
            super(message);
        }
    }

    public static class InvalidToken extends IdentityException {
        public InvalidToken(String message) {
            super(message);
        }
    }

    // -- Registration / Email --

    public static class EmailAlreadyExists extends IdentityException {
        public EmailAlreadyExists(String message) {
            super(message);
        }
    }

    public static class UsernameAlreadyTaken extends IdentityException {
        public UsernameAlreadyTaken(String message) {
            super(message);
        }
    }

    public static class EmailAlreadyVerified extends IdentityException {
        public EmailAlreadyVerified(String message) {
            super(message);
        }
    }

    public static class InvalidVerificationCode extends IdentityException {
        public InvalidVerificationCode(String message) {
            super(message);
        }
    }

    // -- Password --

    public static class InvalidPassword extends IdentityException {
        public InvalidPassword(String message) {
            super(message);
        }
    }

    // -- Profile --

    public static class UserNotFound extends IdentityException {
        public UserNotFound(String message) {
            super(message);
        }
    }

    // -- Rate limiting --

    public static class RateLimitExceeded extends IdentityException {
        public RateLimitExceeded(String message) {
            super(message);
        }
    }
}