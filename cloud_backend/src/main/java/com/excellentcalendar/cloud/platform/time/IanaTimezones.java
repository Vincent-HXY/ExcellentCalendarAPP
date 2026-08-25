package com.excellentcalendar.cloud.platform.time;

import java.time.DateTimeException;
import java.time.ZoneId;
import java.util.Optional;

/**
 * IANA timezone normalization for the wire contract (schema: "IANA timezone identifier").
 * Accepts identifiers that resolve to a named IANA region — including short ids like "UTC"/"GMT"
 * which normalize to their {@code Etc/*} region — and rejects fixed offsets ("+08:00", "Z"),
 * which are offsets, not timezone identifiers. Callers map the failure to their declared code.
 */
public final class IanaTimezones {

    private IanaTimezones() {
    }

    public static Optional<String> tryNormalize(String value) {
        if (value == null || value.isBlank()) {
            return Optional.empty();
        }
        try {
            ZoneId zone = ZoneId.of(value.trim());
            String id = zone.getId();
            return id.contains("/") ? Optional.of(id) : Optional.empty();
        } catch (DateTimeException exception) {
            return Optional.empty();
        }
    }
}
