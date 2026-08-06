package com.excellentcalendar.cloud.platform.api;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.annotation.Nullable;

/**
 * Maps to {@code contracts/common/operation_response.schema.json}.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record OperationResponse(
        @JsonProperty("performed") boolean performed,
        @JsonProperty("message") @Nullable String message
) {

    public static OperationResponse success() {
        return new OperationResponse(true, null);
    }

    public static OperationResponse successWithMessage(String message) {
        return new OperationResponse(true, message);
    }

    public static OperationResponse skipped() {
        return new OperationResponse(false, null);
    }
}