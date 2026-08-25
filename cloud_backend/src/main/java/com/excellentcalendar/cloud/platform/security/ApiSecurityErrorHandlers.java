package com.excellentcalendar.cloud.platform.security;

import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiErrorResponse;
import com.excellentcalendar.cloud.platform.api.ApiResultResponse;
import com.excellentcalendar.cloud.platform.api.ApiResultWriter;
import com.excellentcalendar.cloud.platform.api.RequestContext;
import tools.jackson.databind.ObjectMapper;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;

/**
 * Writes ApiResult envelopes for security-level 401/403 outcomes so non-authenticated requests
 * never fall back to framework error pages.
 */
public class ApiSecurityErrorHandlers {

    private ApiSecurityErrorHandlers() {
    }

    public static final class EntryPoint implements AuthenticationEntryPoint {

        private final ObjectMapper objectMapper;

        public EntryPoint(ObjectMapper objectMapper) {
            this.objectMapper = objectMapper;
        }

        @Override
        public void commence(
                HttpServletRequest request,
                HttpServletResponse response,
                AuthenticationException authException) throws IOException, ServletException {
            ApiResultResponse<Void> envelope = ApiResultResponse.failure(
                    ApiErrorResponse.of(ApiErrorCode.API_UNAUTHENTICATED), RequestContext.requestId());
            ApiResultWriter.write(response, objectMapper, ApiErrorCode.API_UNAUTHENTICATED.httpStatus(), envelope);
        }
    }

    public static final class DeniedHandler implements AccessDeniedHandler {

        private final ObjectMapper objectMapper;

        public DeniedHandler(ObjectMapper objectMapper) {
            this.objectMapper = objectMapper;
        }

        @Override
        public void handle(
                HttpServletRequest request,
                HttpServletResponse response,
                AccessDeniedException accessDeniedException) throws IOException, ServletException {
            ApiResultResponse<Void> envelope = ApiResultResponse.failure(
                    ApiErrorResponse.of(ApiErrorCode.API_FORBIDDEN), RequestContext.requestId());
            ApiResultWriter.write(response, objectMapper, ApiErrorCode.API_FORBIDDEN.httpStatus(), envelope);
        }
    }
}
