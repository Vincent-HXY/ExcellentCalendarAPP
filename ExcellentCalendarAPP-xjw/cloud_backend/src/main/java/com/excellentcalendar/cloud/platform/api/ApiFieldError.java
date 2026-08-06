package com.excellentcalendar.cloud.platform.api;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Maps to {@code contracts/common/api_field_error.schema.json}.
 */
public record ApiFieldError(
        @JsonProperty("field") String field,
        @JsonProperty("code") String code,
        @JsonProperty("message") String message
) {
}