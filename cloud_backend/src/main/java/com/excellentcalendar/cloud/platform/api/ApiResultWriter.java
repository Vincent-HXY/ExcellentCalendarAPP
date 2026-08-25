package com.excellentcalendar.cloud.platform.api;

import tools.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.MediaType;

/**
 * Serializes ApiResult envelopes directly to the HTTP response; used by security
 * filters and entry points that run outside controller advice.
 */
public final class ApiResultWriter {

    private ApiResultWriter() {
    }

    public static void write(
            HttpServletResponse response,
            ObjectMapper objectMapper,
            int httpStatus,
            ApiResultResponse<?> envelope) throws IOException {
        response.setStatus(httpStatus);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        objectMapper.writeValue(response.getOutputStream(), envelope);
    }
}
