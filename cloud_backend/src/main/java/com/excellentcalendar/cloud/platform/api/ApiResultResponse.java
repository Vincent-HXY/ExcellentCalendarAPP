package com.excellentcalendar.cloud.platform.api;

/**
 * Unified HTTP envelope; matches {@code contracts/common/api_result.schema.json}.
 * {@code contractVersion} is fixed to {@code 1} (Backend API v1).
 */
public record ApiResultResponse<T>(
        boolean ok,
        T data,
        ApiErrorResponse error,
        int contractVersion,
        String requestId) {

    public static final int CONTRACT_VERSION = 1;

    public static <T> ApiResultResponse<T> success(T data, String requestId) {
        return new ApiResultResponse<>(true, data, null, CONTRACT_VERSION, requestId);
    }

    public static <T> ApiResultResponse<T> failure(ApiErrorResponse error, String requestId) {
        return new ApiResultResponse<>(false, null, error, CONTRACT_VERSION, requestId);
    }
}
