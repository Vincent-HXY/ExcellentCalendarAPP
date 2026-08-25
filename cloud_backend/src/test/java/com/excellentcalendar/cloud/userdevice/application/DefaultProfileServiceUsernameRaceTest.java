package com.excellentcalendar.cloud.userdevice.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiException;
import com.excellentcalendar.cloud.userdevice.infrastructure.persistence.UserPreferencesRepository;
import com.excellentcalendar.cloud.userdevice.infrastructure.persistence.UserProfileEntity;
import com.excellentcalendar.cloud.userdevice.infrastructure.persistence.UserProfileRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

/**
 * The unique index is the final concurrency guard: when two PATCHes race past the pre-check, the
 * losing flush must map to AUTH_USERNAME_ALREADY_EXISTS (409) instead of leaking a 500.
 */
class DefaultProfileServiceUsernameRaceTest {

    private final UserProfileRepository profileRepository = mock(UserProfileRepository.class);
    private final UserPreferencesRepository preferencesRepository = mock(UserPreferencesRepository.class);
    private final DefaultProfileService service = new DefaultProfileService(
            profileRepository,
            preferencesRepository,
            Clock.fixed(Instant.parse("2026-08-17T12:00:00Z"), ZoneId.of("UTC")));

    @Test
    void concurrentUsernameConflictAtFlushMapsToDeclaredCode() {
        UUID userId = UUID.randomUUID();
        UserProfileEntity profile = new UserProfileEntity(
                userId, "old_name", "old_name", "Display", Instant.parse("2026-08-17T11:00:00Z"));
        when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));
        when(profileRepository.existsByNormalizedUsernameAndUserIdNot("taken_name", userId)).thenReturn(false);
        when(profileRepository.saveAndFlush(any()))
                .thenThrow(new DataIntegrityViolationException(
                        "could not execute statement; constraint [uq_user_profiles_normalized_username]"));

        assertThatThrownBy(() -> service.updateProfile(
                userId, new ProfileService.ProfileUpdate("taken_name", null)))
                .isInstanceOfSatisfying(ApiException.class, exception -> {
                    assertThat(exception.code()).isEqualTo(ApiErrorCode.AUTH_USERNAME_ALREADY_EXISTS);
                    assertThat(exception.fieldErrors()).hasSize(1);
                    assertThat(exception.fieldErrors().get(0).field()).isEqualTo("username");
                });
    }

    @Test
    void unknownConstraintViolationIsNotMisclassified() {
        UUID userId = UUID.randomUUID();
        UserProfileEntity profile = new UserProfileEntity(
                userId, "old_name", "old_name", "Display", Instant.parse("2026-08-17T11:00:00Z"));
        when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));
        when(profileRepository.existsByNormalizedUsernameAndUserIdNot("new_name", userId)).thenReturn(false);
        when(profileRepository.saveAndFlush(any()))
                .thenThrow(new DataIntegrityViolationException("some unrelated constraint [ck_other]"));

        assertThatThrownBy(() -> service.updateProfile(
                userId, new ProfileService.ProfileUpdate("new_name", null)))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
