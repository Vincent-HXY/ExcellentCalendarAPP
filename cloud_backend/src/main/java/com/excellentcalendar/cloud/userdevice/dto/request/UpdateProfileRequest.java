package com.excellentcalendar.cloud.userdevice.dto.request;

import jakarta.validation.constraints.Size;

public record UpdateProfileRequest(
        @Size(min = 1, max = 100) String displayName,
        @Size(min = 3, max = 50) String username,
        @Size(max = 10) String language,
        @Size(max = 50) String timezone) {
}