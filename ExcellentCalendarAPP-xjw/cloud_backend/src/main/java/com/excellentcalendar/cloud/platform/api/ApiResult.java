package com.excellentcalendar.cloud.platform.api;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.annotation.Nullable;
import java.util.List;

/**
 * Unified backend API result envelope.
 * Maps to {@code contracts/common/api_result.schema.json}.
 *
 * @param <T> the data type carried on success
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiResult<T>(
        @JsonProperty("ok") boolean ok,
        @JsonProperty("data") @Nullable T data,
        @JsonProperty("error") @Nullable ApiError error,
        @JsonProperty("contract_version") int contractVersion,
        @JsonProperty("request_id") String requestId
) {

    public static <T> ApiResult<T> success(T data, String requestId) {
        return new ApiResult<>(true, data, null, 1, requestId);
    }

    public static ApiResult<Void> failure(
            String code,
            String message,
            boolean retryable,
            @Nullable List<ApiFieldError> fieldErrors,
            @Nullable Integer retryAfterSeconds,
            String requestId) {
        var error = new ApiError(code, message, retryable,
                fieldErrors != null ? fieldErrors : List.of(),
                retryAfterSeconds);
        return new ApiResult<>(false, null, error, 1, requestId);
    }

    @SuppressWarnings("unchecked")
    public static <T> ApiResult<T> failureTyped(
            String code, String message, boolean retryable,
            @Nullable List<ApiFieldError> fieldErrors,
            @Nullable Integer retryAfterSeconds,
            String requestId) {
        return (ApiResult<T>) (ApiResult<?>) failure(code, message, retryable, fieldErrors, retryAfterSeconds, requestId);
    }

    public static ApiResult<Void> failure(String code, String message, boolean retryable, String requestId) {
        return failure(code, message, retryable, List.of(), null, requestId);
    }
}