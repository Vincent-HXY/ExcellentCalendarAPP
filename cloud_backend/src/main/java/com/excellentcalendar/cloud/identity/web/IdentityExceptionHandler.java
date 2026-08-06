package com.excellentcalendar.cloud.identity.web;

import com.excellentcalendar.cloud.identity.service.IdentityException;
import com.excellentcalendar.cloud.platform.web.ProblemDetailFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(basePackageClasses = IdentityExceptionHandler.class)
public class IdentityExceptionHandler {

    @ExceptionHandler(IdentityException.InvalidCredentials.class)
    public ProblemDetail handleInvalidCredentials(IdentityException.InvalidCredentials ex) {
        return ProblemDetailFactory.problem(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", ex.getMessage());
    }

    @ExceptionHandler(IdentityException.AccountDisabled.class)
    public ProblemDetail handleAccountDisabled(IdentityException.AccountDisabled ex) {
        return ProblemDetailFactory.problem(HttpStatus.FORBIDDEN, "ACCOUNT_DISABLED", ex.getMessage());
    }

    @ExceptionHandler(IdentityException.InvalidToken.class)
    public ProblemDetail handleInvalidToken(IdentityException.InvalidToken ex) {
        return ProblemDetailFactory.problem(HttpStatus.UNAUTHORIZED, "INVALID_TOKEN", ex.getMessage());
    }

    @ExceptionHandler(IdentityException.EmailAlreadyExists.class)
    public ProblemDetail handleEmailAlreadyExists(IdentityException.EmailAlreadyExists ex) {
        return ProblemDetailFactory.problem(HttpStatus.CONFLICT, "EMAIL_ALREADY_EXISTS", ex.getMessage());
    }

    @ExceptionHandler(IdentityException.UsernameAlreadyTaken.class)
    public ProblemDetail handleUsernameAlreadyTaken(IdentityException.UsernameAlreadyTaken ex) {
        return ProblemDetailFactory.problem(HttpStatus.CONFLICT, "USERNAME_ALREADY_TAKEN", ex.getMessage());
    }

    @ExceptionHandler(IdentityException.EmailAlreadyVerified.class)
    public ProblemDetail handleEmailAlreadyVerified(IdentityException.EmailAlreadyVerified ex) {
        return ProblemDetailFactory.problem(HttpStatus.BAD_REQUEST, "EMAIL_ALREADY_VERIFIED", ex.getMessage());
    }

    @ExceptionHandler(IdentityException.InvalidVerificationCode.class)
    public ProblemDetail handleInvalidVerificationCode(IdentityException.InvalidVerificationCode ex) {
        return ProblemDetailFactory.problem(HttpStatus.BAD_REQUEST, "INVALID_VERIFICATION_CODE", ex.getMessage());
    }

    @ExceptionHandler(IdentityException.InvalidPassword.class)
    public ProblemDetail handleInvalidPassword(IdentityException.InvalidPassword ex) {
        return ProblemDetailFactory.problem(HttpStatus.BAD_REQUEST, "INVALID_PASSWORD", ex.getMessage());
    }

    @ExceptionHandler(IdentityException.UserNotFound.class)
    public ProblemDetail handleUserNotFound(IdentityException.UserNotFound ex) {
        return ProblemDetailFactory.problem(HttpStatus.NOT_FOUND, "USER_NOT_FOUND", ex.getMessage());
    }

    @ExceptionHandler(IdentityException.RateLimitExceeded.class)
    public ProblemDetail handleRateLimitExceeded(IdentityException.RateLimitExceeded ex) {
        return ProblemDetailFactory.problem(HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMIT_EXCEEDED", ex.getMessage());
    }
}