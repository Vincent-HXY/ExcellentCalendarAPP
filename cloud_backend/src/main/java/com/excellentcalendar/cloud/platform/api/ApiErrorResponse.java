package com.excellentcalendar.cloud.platform.api;

import java.util.List;

/**
 * Error half of the {@code ApiResult} envelope; matches
 * {@code contracts/common/api_error.schema.json}.
 */
public record ApiErrorResponse(
        String code,
        String message,
        boolean retryable,
        List<ApiFieldErrorResponse> fieldErrors,
        Integer retryAfterSeconds,
        ApiErrorContextResponse context) {

    public static ApiErrorResponse of(ApiErrorCode code) {
        return new ApiErrorResponse(
                code.code(), code.message(), code.retryable(), List.of(), null, null);
    }

    public static ApiErrorResponse of(ApiErrorCode code, List<ApiFieldErrorResponse> fieldErrors) {
        return new ApiErrorResponse(code.code(), code.message(), code.retryable(), fieldErrors, null, null);
    }

    public static ApiErrorResponse withRetryAfter(ApiErrorCode code, int retryAfterSeconds) {
        return new ApiErrorResponse(
                code.code(), code.message(), code.retryable(), List.of(), retryAfterSeconds, null);
    }

    public static ApiErrorResponse withContext(ApiErrorCode code, ApiErrorContextResponse context) {
        return new ApiErrorResponse(code.code(), code.message(), code.retryable(), List.of(), null, context);
    }
}
