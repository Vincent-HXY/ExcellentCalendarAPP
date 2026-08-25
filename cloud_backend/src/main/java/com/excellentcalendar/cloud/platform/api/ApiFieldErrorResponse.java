package com.excellentcalendar.cloud.platform.api;

import java.util.List;

/**
 * Single field error of {@link ApiErrorResponse}; matches
 * {@code contracts/common/api_field_error.schema.json}.
 */
public record ApiFieldErrorResponse(String field, String code, String message) {

    public static List<ApiFieldErrorResponse> none() {
        return List.of();
    }
}
