package com.excellentcalendar.cloud.identity.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.excellentcalendar.cloud.identity.dto.request.UpdateProfileRequest;
import com.excellentcalendar.cloud.identity.dto.response.ProfileResponse;
import com.excellentcalendar.cloud.identity.model.UserAccount;
import com.excellentcalendar.cloud.identity.repository.UserAccountRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class UserProfileServiceTest {

    @Mock
    private UserAccountRepository userAccountRepository;

    private UserProfileService service;
    private UUID userId;
    private UserAccount account;

    @BeforeEach
    void setUp() {
        service = new UserProfileService(userAccountRepository);
        userId = UUID.randomUUID();

        account = new UserAccount("test@example.com", "testuser", "Test User", "hashed-password");
        account.setId(userId);

        // Make save() return the same account (default mock returns null)
        lenient().when(userAccountRepository.save(any(UserAccount.class))).thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Nested
    @DisplayName("getProfile()")
    class GetProfile {

        @Test
        @DisplayName("should return ProfileResponse when account exists")
        void shouldReturnProfileResponse_whenAccountExists() {
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));

            ProfileResponse response = service.getProfile(userId);

            assertThat(response).isNotNull();
            assertThat(response.userId()).isEqualTo(userId);
            assertThat(response.email()).isEqualTo("test@example.com");
            assertThat(response.displayName()).isEqualTo("Test User");
            assertThat(response.username()).isEqualTo("testuser");
        }

        @Test
        @DisplayName("should throw UserNotFound when account does not exist")
        void shouldThrowUserNotFound_whenAccountDoesNotExist() {
            when(userAccountRepository.findById(userId)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.getProfile(userId))
                    .isInstanceOf(IdentityException.UserNotFound.class);
        }
    }

    @Nested
    @DisplayName("updateProfile()")
    class UpdateProfile {

        @Test
        @DisplayName("should update displayName and return updated profile")
        void shouldUpdateDisplayName() {
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));
            UpdateProfileRequest request = new UpdateProfileRequest("New Name", null, null, null);

            ProfileResponse response = service.updateProfile(userId, request);

            assertThat(response.displayName()).isEqualTo("New Name");
            verify(userAccountRepository).save(account);
        }

        @Test
        @DisplayName("should throw UsernameAlreadyTaken when username exists")
        void shouldThrowUsernameAlreadyTaken_whenUsernameExists() {
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));
            when(userAccountRepository.existsByUsernameIgnoreCase("taken-username")).thenReturn(true);
            UpdateProfileRequest request = new UpdateProfileRequest(null, "taken-username", null, null);

            assertThatThrownBy(() -> service.updateProfile(userId, request))
                    .isInstanceOf(IdentityException.UsernameAlreadyTaken.class);
        }

        @Test
        @DisplayName("should not save when nothing changed")
        void shouldNotSave_whenNothingChanged() {
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));
            UpdateProfileRequest request = new UpdateProfileRequest(null, null, null, null);

            service.updateProfile(userId, request);

            verify(userAccountRepository, never()).save(any());
        }
    }

    @Nested
    @DisplayName("updateAvatar()")
    class UpdateAvatar {

        @Test
        @DisplayName("should update avatar URL and return profile")
        void shouldUpdateAvatarUrl() {
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));
            String avatarUrl = "https://example.com/avatar.jpg";

            ProfileResponse response = service.updateAvatar(userId, avatarUrl);

            assertThat(response.avatarUrl()).isEqualTo(avatarUrl);
            verify(userAccountRepository).save(account);
        }
    }

    @Nested
    @DisplayName("deleteAvatar()")
    class DeleteAvatar {

        @Test
        @DisplayName("should delete avatar URL")
        void shouldDeleteAvatarUrl() {
            account.setAvatarUrl("https://example.com/avatar.jpg");
            when(userAccountRepository.findById(userId)).thenReturn(Optional.of(account));

            service.deleteAvatar(userId);

            assertThat(account.getAvatarUrl()).isNull();
            verify(userAccountRepository).save(account);
        }

        @Test
        @DisplayName("should throw UserNotFound when account does not exist")
        void shouldThrowUserNotFound_whenAccountDoesNotExist() {
            when(userAccountRepository.findById(userId)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.deleteAvatar(userId))
                    .isInstanceOf(IdentityException.UserNotFound.class);
        }
    }
}