package com.excellentcalendar.cloud.platform.api;

import jakarta.annotation.Nullable;
import java.util.List;
import org.springframework.http.HttpStatus;

/**
 * Business exception that maps to an {@link ApiResult} error response.
 */
public class ApiException extends RuntimeException {

    private final String code;
    private final boolean retryable;
    private final HttpStatus httpStatus;
    private final transient List<ApiFieldError> fieldErrors;
    private final transient Integer retryAfterSeconds;

    public ApiException(String code, String message, boolean retryable, HttpStatus httpStatus) {
        this(code, message, retryable, httpStatus, List.of(), null);
    }

    public ApiException(
            String code, String message, boolean retryable, HttpStatus httpStatus,
            @Nullable List<ApiFieldError> fieldErrors,
            @Nullable Integer retryAfterSeconds) {
        super(message);
        this.code = code;
        this.retryable = retryable;
        this.httpStatus = httpStatus;
        this.fieldErrors = fieldErrors != null ? fieldErrors : List.of();
        this.retryAfterSeconds = retryAfterSeconds;
    }

    public String getCode() { return code; }
    public boolean isRetryable() { return retryable; }
    public HttpStatus getHttpStatus() { return httpStatus; }
    public List<ApiFieldError> getFieldErrors() { return fieldErrors; }
    public Integer getRetryAfterSeconds() { return retryAfterSeconds; }
}