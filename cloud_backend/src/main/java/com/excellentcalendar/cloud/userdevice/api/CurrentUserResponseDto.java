package com.excellentcalendar.cloud.userdevice.api;

public record CurrentUserResponseDto(
        UserAccountResponseDto account,
        UserProfileResponseDto profile,
        UserPreferencesResponseDto preferences) {
}
