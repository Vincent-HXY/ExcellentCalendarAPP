package com.excellentcalendar.cloud.platform.api;

import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Translates exceptions into {@link ApiResult} error responses.
 * No stack traces, passwords, tokens, or sensitive data are leaked.
 */
@Profile("api")
@RestControllerAdvice
class GlobalExceptionHandler {

    private static final Logger LOGGER = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private static final String VALIDATION_CODE = "API_VALIDATION_FAILED";
    private static final String UNAUTHENTICATED_CODE = "API_UNAUTHENTICATED";
    private static final String FORBIDDEN_CODE = "API_FORBIDDEN";
    private static final String INTERNAL_ERROR_CODE = "API_INTERNAL_ERROR";

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ApiResult<Void>> handleValidation(
            MethodArgumentNotValidException ex,
            HttpServletRequest request) {
        List<ApiFieldError> fieldErrors = ex.getBindingResult().getAllErrors().stream()
                .map(err -> {
                    String field = (err instanceof FieldError fe) ? fe.getField() : err.getObjectName();
                    return new ApiFieldError(field, VALIDATION_CODE, err.getDefaultMessage());
                })
                .toList();
        var result = ApiResult.failure(
                VALIDATION_CODE, "Request validation failed", false,
                fieldErrors, null, requestId(request));
        return ResponseEntity.badRequest().body(result);
    }

    @ExceptionHandler(AuthenticationException.class)
    ResponseEntity<ApiResult<Void>> handleAuthentication(AuthenticationException ex, HttpServletRequest request) {
        var result = ApiResult.failure(
                UNAUTHENTICATED_CODE, "Authentication is required", false, requestId(request));
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(result);
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ApiResult<Void>> handleAccessDenied(AccessDeniedException ex, HttpServletRequest request) {
        var result = ApiResult.failure(
                FORBIDDEN_CODE, "The authenticated user is not allowed to perform this operation",
                false, requestId(request));
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(result);
    }

    @ExceptionHandler(ApiException.class)
    ResponseEntity<ApiResult<Void>> handleApiException(ApiException ex, HttpServletRequest request) {
        var result = ApiResult.failure(
                ex.getCode(), ex.getMessage(), ex.isRetryable(),
                ex.getFieldErrors(), ex.getRetryAfterSeconds(), requestId(request));
        return ResponseEntity.status(ex.getHttpStatus()).body(result);
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ApiResult<Void>> handleUnhandled(Exception ex, HttpServletRequest request) {
        LOGGER.error("Unhandled exception for request_id={}", requestId(request), ex);
        var result = ApiResult.failure(
                INTERNAL_ERROR_CODE, "Backend service failed to process the request",
                true, requestId(request));
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(result);
    }

    private static String requestId(HttpServletRequest request) {
        return RequestIdUtils.getRequestId(request);
    }
}