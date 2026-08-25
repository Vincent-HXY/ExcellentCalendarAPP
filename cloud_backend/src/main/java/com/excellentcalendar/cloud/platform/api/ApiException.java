package com.excellentcalendar.cloud.platform.api;

import java.util.List;

/**
 * Business/protocol failure carrying the contract error code, optional field errors,
 * rate-limit retry hint and typed context. Mapped to the ApiResult envelope by
 * {@link GlobalApiExceptionHandler}.
 */
public class ApiException extends RuntimeException {

    private final ApiErrorCode code;
    private final List<ApiFieldErrorResponse> fieldErrors;
    private final Integer retryAfterSeconds;
    private final ApiErrorContextResponse context;

    public ApiException(ApiErrorCode code) {
        this(code, code.message(), List.of(), null, null);
    }

    public ApiException(ApiErrorCode code, List<ApiFieldErrorResponse> fieldErrors) {
        this(code, code.message(), fieldErrors, null, null);
    }

    public ApiException(ApiErrorCode code, int retryAfterSeconds) {
        this(code, code.message(), List.of(), retryAfterSeconds, null);
    }

    public ApiException(ApiErrorCode code, ApiErrorContextResponse context) {
        this(code, code.message(), List.of(), null, context);
    }

    public ApiException(
            ApiErrorCode code,
            String message,
            List<ApiFieldErrorResponse> fieldErrors,
            Integer retryAfterSeconds,
            ApiErrorContextResponse context) {
        super(message);
        this.code = code;
        this.fieldErrors = fieldErrors;
        this.retryAfterSeconds = retryAfterSeconds;
        this.context = context;
    }

    public ApiErrorCode code() {
        return code;
    }

    public List<ApiFieldErrorResponse> fieldErrors() {
        return fieldErrors;
    }

    public Integer retryAfterSeconds() {
        return retryAfterSeconds;
    }

    public ApiErrorContextResponse context() {
        return context;
    }

    public ApiErrorResponse toErrorResponse() {
        return new ApiErrorResponse(
                code.code(), getMessage(), code.retryable(), fieldErrors, retryAfterSeconds, context);
    }
}
