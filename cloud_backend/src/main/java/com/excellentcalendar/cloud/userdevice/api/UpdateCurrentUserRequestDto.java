package com.excellentcalendar.cloud.userdevice.api;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.Map;

/**
 * PATCH body for user.update_current: every field is optional; absent fields are kept. None of the
 * fields accepts explicit null (contract schema has no nullable branches) and an empty object
 * violates {@code minProperties: 1} — both are enforced by the controller at the protocol layer.
 */
public record UpdateCurrentUserRequestDto(
        @Pattern(regexp = "^[a-z0-9_]{3,24}$", message = "username must match [a-z0-9_]{3,24}")
        String username,
        @CodePointLength(min = 1, max = 40, message = "display_name must have 1-40 Unicode code points")
        String displayName,
        @Pattern(regexp = "^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$", message = "locale is not a BCP 47 language tag")
        @Size(max = 35)
        String locale,
        @Size(min = 1, max = 64)
        String timezone,
        // The schema has no minItems: an empty array clears the configured reminder methods.
        @Size(max = 3, message = "default_reminder_methods holds at most the 3 declared values")
        List<@Pattern(regexp = "^(ring|popup|wechat)$") String> defaultReminderMethods,
        Map<String, Object> settings) {
}
