package com.excellentcalendar.cloud.platform.api;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.annotation.Nullable;
import java.util.List;

/**
 * Maps to {@code contracts/common/api_error.schema.json}.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiError(
        @JsonProperty("code") String code,
        @JsonProperty("message") String message,
        @JsonProperty("retryable") boolean retryable,
        @JsonProperty("field_errors") List<ApiFieldError> fieldErrors,
        @JsonProperty("retry_after_seconds") @Nullable Integer retryAfterSeconds
) {
}