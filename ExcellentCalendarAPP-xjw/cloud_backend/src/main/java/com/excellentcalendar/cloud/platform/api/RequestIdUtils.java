package com.excellentcalendar.cloud.platform.api;

import jakarta.servlet.http.HttpServletRequest;

/**
 * Shared utility for accessing the request ID from the HTTP request attribute.
 * This is the public API alternative to referencing the internal {@code RequestIdFilter} directly.
 */
public final class RequestIdUtils {

    public static final String REQUEST_ID_ATTRIBUTE =
            "com.excellentcalendar.cloud.platform.observability.RequestIdFilter.requestId";

    private RequestIdUtils() {}

    /**
     * Extracts the request ID from the current HTTP request.
     *
     * @param request the HTTP request
     * @return the request ID, or "unknown" if not set
     */
    public static String getRequestId(HttpServletRequest request) {
        Object attr = request.getAttribute(REQUEST_ID_ATTRIBUTE);
        return attr != null ? attr.toString() : "unknown";
    }
}