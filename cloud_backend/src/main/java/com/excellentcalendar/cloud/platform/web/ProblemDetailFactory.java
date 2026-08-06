package com.excellentcalendar.cloud.platform.web;

import java.time.Instant;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;

/**
 * Shared factory for creating {@link ProblemDetail} responses across all modules.
 *
 * <p>Both the identity and userdevice modules need the same {@code ProblemDetail}
 * shape ({@code title} as an error code, {@code detail} as a human-readable message,
 * and a {@code timestamp} property). This class avoids duplicating that logic.
 */
public final class ProblemDetailFactory {

    private ProblemDetailFactory() {
        // utility class
    }

    /**
     * Create a {@link ProblemDetail} with the given status, error code (title),
     * and detail message. A {@code timestamp} property is set automatically.
     *
     * @param status HTTP status
     * @param code   machine-readable error code (e.g. {@code INVALID_CREDENTIALS})
     * @param detail human-readable detail message
     * @return a new {@link ProblemDetail} instance
     */
    public static ProblemDetail problem(HttpStatus status, String code, String detail) {
        ProblemDetail pd = ProblemDetail.forStatus(status);
        pd.setTitle(code);
        pd.setDetail(detail);
        pd.setProperty("timestamp", Instant.now());
        return pd;
    }
}