package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.userdevice.api.AvatarInfoResponseDto;
import com.excellentcalendar.cloud.userdevice.api.CurrentUserResponseDto;
import com.excellentcalendar.cloud.userdevice.api.UserAccountResponseDto;
import com.excellentcalendar.cloud.userdevice.api.UserPreferencesResponseDto;
import com.excellentcalendar.cloud.userdevice.api.UserProfileResponseDto;

public record AuthenticationResponseDto(
        CurrentUserResponseDto currentUser,
        TokenPairResponseDto tokens) {

    public static AuthenticationResponseDto from(
            AuthenticationResults.Authentication result, AvatarInfoResponseDto avatar) {
        AuthenticationResults.CurrentUser user = result.currentUser();
        return new AuthenticationResponseDto(
                new CurrentUserResponseDto(
                        new UserAccountResponseDto(
                                user.accountId(),
                                user.email(),
                                user.status(),
                                user.emailVerifiedAt(),
                                user.accountCreatedAt(),
                                user.accountUpdatedAt()),
                        new UserProfileResponseDto(
                                user.profileUserId(),
                                user.username(),
                                user.displayName(),
                                avatar,
                                user.profileCreatedAt(),
                                user.profileUpdatedAt()),
                        new UserPreferencesResponseDto(
                                user.preferencesUserId(),
                                user.locale(),
                                user.timezone(),
                                user.defaultReminderMethods(),
                                user.settings(),
                                user.preferencesCreatedAt(),
                                user.preferencesUpdatedAt())),
                TokenPairResponseDto.from(result.tokens()));
    }
}
