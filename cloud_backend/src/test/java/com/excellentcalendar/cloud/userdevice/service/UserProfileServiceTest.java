package com.excellentcalendar.cloud.userdevice.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.excellentcalendar.cloud.userdevice.dto.request.UpdateProfileRequest;
import com.excellentcalendar.cloud.userdevice.dto.response.UserProfileResponse;
import com.excellentcalendar.cloud.userdevice.model.UserProfile;
import com.excellentcalendar.cloud.userdevice.repository.UserProfileRepository;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.web.multipart.MultipartFile;

@ExtendWith(MockitoExtension.class)
class UserProfileServiceTest {

    @Mock
    private UserProfileRepository profileRepository;

    private UserProfileService service;
    private UUID userId;
    private UserProfile profile;

    @BeforeEach
    void setUp() {
        service = new UserProfileService(profileRepository);
        userId = UUID.randomUUID();

        profile = new UserProfile(userId, "Test User", "testuser", Instant.now());
        profile.setLanguage("en");
        profile.setTimezone("UTC");

        // Make save() return the same profile (default mock returns null)
        lenient().when(profileRepository.save(any(UserProfile.class))).thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Nested
    @DisplayName("getProfile()")
    class GetProfile {

        @Test
        @DisplayName("should return UserProfileResponse when profile exists")
        void shouldReturnProfile_whenExists() {
            when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));

            UserProfileResponse response = service.getProfile(userId);

            assertThat(response).isNotNull();
            assertThat(response.userId()).isEqualTo(userId);
            assertThat(response.displayName()).isEqualTo("Test User");
        }

        @Test
        @DisplayName("should create default profile when profile does not exist")
        void shouldCreateDefaultProfile_whenNotExists() {
            when(profileRepository.findById(userId)).thenReturn(Optional.empty());
            when(profileRepository.existsById(userId)).thenReturn(false);
            when(profileRepository.save(any(UserProfile.class))).thenAnswer(invocation -> {
                UserProfile saved = invocation.getArgument(0);
                return saved;
            });

            UserProfileResponse response = service.getProfile(userId);

            assertThat(response).isNotNull();
            assertThat(response.displayName()).startsWith("User");
            verify(profileRepository).save(any(UserProfile.class));
        }
    }

    @Nested
    @DisplayName("updateProfile()")
    class UpdateProfile {

        @Test
        @DisplayName("should update displayName and return updated profile")
        void shouldUpdateDisplayName() {
            when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));
            UpdateProfileRequest request = new UpdateProfileRequest("New Name", null, null, null);

            UserProfileResponse response = service.updateProfile(userId, request);

            assertThat(response.displayName()).isEqualTo("New Name");
            verify(profileRepository).save(profile);
        }

        @Test
        @DisplayName("should throw UsernameAlreadyTaken when username exists")
        void shouldThrowUsernameAlreadyTaken_whenUsernameExists() {
            when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));
            when(profileRepository.existsByUsernameIgnoreCase("taken-username")).thenReturn(true);
            UpdateProfileRequest request = new UpdateProfileRequest(null, "taken-username", null, null);

            assertThatThrownBy(() -> service.updateProfile(userId, request))
                    .isInstanceOf(UserDeviceException.UsernameAlreadyTaken.class);
        }

        @Test
        @DisplayName("should not save when nothing changed")
        void shouldNotSave_whenNothingChanged() {
            when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));
            UpdateProfileRequest request = new UpdateProfileRequest(null, null, null, null);

            service.updateProfile(userId, request);

            verify(profileRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("uploadAvatar()")
    class UploadAvatar {

        @Test
        @DisplayName("should upload avatar when file is valid JPEG")
        void shouldUploadAvatar_whenValidJpeg() throws Exception {
            when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));
            byte[] jpegBytes = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0, 0, 0, 0, 0};
            MultipartFile file = new MockMultipartFile(
                    "file", "avatar.jpg", "image/jpeg", jpegBytes);

            UserProfileResponse response = service.uploadAvatar(userId, file);

            assertThat(response).isNotNull();
            verify(profileRepository).save(profile);
            assertThat(profile.getAvatarPath()).isNotNull();
        }

        @Test
        @DisplayName("should throw FileTooLarge when file exceeds 5MB")
        void shouldThrowFileTooLarge_whenFileExceeds5MB() {
            when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));
            byte[] largeBytes = new byte[6 * 1024 * 1024];
            MultipartFile file = new MockMultipartFile(
                    "file", "large.jpg", "image/jpeg", largeBytes);

            assertThatThrownBy(() -> service.uploadAvatar(userId, file))
                    .isInstanceOf(UserDeviceException.FileTooLarge.class);
        }

        @Test
        @DisplayName("should throw InvalidFileType when MIME type is invalid")
        void shouldThrowInvalidFileType_whenInvalidMimeType() {
            when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));
            byte[] gifBytes = {'G', 'I', 'F', '8', 0, 0, 0, 0};
            MultipartFile file = new MockMultipartFile(
                    "file", "image.gif", "image/gif", gifBytes);

            assertThatThrownBy(() -> service.uploadAvatar(userId, file))
                    .isInstanceOf(UserDeviceException.InvalidFileType.class);
        }
    }

    @Nested
    @DisplayName("deleteAvatar()")
    class DeleteAvatar {

        @Test
        @DisplayName("should delete avatar when profile has one")
        void shouldDeleteAvatar_whenExists() {
            profile.setAvatarPath("uploads/avatars/test.jpg");
            when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));

            UserProfileResponse response = service.deleteAvatar(userId);

            assertThat(response).isNotNull();
            assertThat(profile.getAvatarPath()).isNull();
            verify(profileRepository).save(profile);
        }

        @Test
        @DisplayName("should not call save when profile has no avatar")
        void shouldNotCallSave_whenNoAvatar() {
            when(profileRepository.findById(userId)).thenReturn(Optional.of(profile));

            UserProfileResponse response = service.deleteAvatar(userId);

            assertThat(response).isNotNull();
            verify(profileRepository, never()).save(any());
        }
    }
}