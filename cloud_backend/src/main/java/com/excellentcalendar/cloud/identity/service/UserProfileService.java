package com.excellentcalendar.cloud.identity.service;

import com.excellentcalendar.cloud.identity.dto.request.UpdateProfileRequest;
import com.excellentcalendar.cloud.identity.dto.response.ProfileResponse;
import com.excellentcalendar.cloud.identity.model.UserAccount;
import com.excellentcalendar.cloud.identity.repository.UserAccountRepository;
import java.time.Instant;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class UserProfileService {

    private final UserAccountRepository userAccountRepository;

    public UserProfileService(UserAccountRepository userAccountRepository) {
        this.userAccountRepository = userAccountRepository;
    }

    @Transactional(readOnly = true)
    public ProfileResponse getProfile(UUID userId) {
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(() -> new IdentityException.UserNotFound("User not found"));
        return toProfileResponse(account);
    }

    public ProfileResponse updateProfile(UUID userId, UpdateProfileRequest request) {
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(() -> new IdentityException.UserNotFound("User not found"));

        boolean changed = false;

        if (request.displayName() != null && !request.displayName().isBlank()
                && !request.displayName().equals(account.getDisplayName())) {
            account.setDisplayName(request.displayName().trim());
            changed = true;
        }

        if (request.username() != null && !request.username().isBlank()
                && !request.username().equals(account.getUsername())) {
            // Check uniqueness
            if (userAccountRepository.existsByUsernameIgnoreCase(request.username())) {
                throw new IdentityException.UsernameAlreadyTaken("Username is already taken");
            }
            account.setUsername(request.username().trim());
            changed = true;
        }

        if (request.language() != null && !request.language().isBlank()
                && !request.language().equals(account.getLanguage())) {
            account.setLanguage(request.language().trim());
            changed = true;
        }

        if (request.timezone() != null && !request.timezone().isBlank()
                && !request.timezone().equals(account.getTimezone())) {
            account.setTimezone(request.timezone().trim());
            changed = true;
        }

        if (changed) {
            account.setUpdatedAt(Instant.now());
            account = userAccountRepository.save(account);
        }

        return toProfileResponse(account);
    }

    public ProfileResponse updateAvatar(UUID userId, String avatarUrl) {
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(() -> new IdentityException.UserNotFound("User not found"));

        account.setAvatarUrl(avatarUrl);
        account.setUpdatedAt(Instant.now());
        account = userAccountRepository.save(account);

        return toProfileResponse(account);
    }

    public void deleteAvatar(UUID userId) {
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(() -> new IdentityException.UserNotFound("User not found"));

        account.setAvatarUrl(null);
        account.setUpdatedAt(Instant.now());
        userAccountRepository.save(account);
    }

    private ProfileResponse toProfileResponse(UserAccount account) {
        return new ProfileResponse(
                account.getId(),
                account.getEmail(),
                account.getUsername(),
                account.getDisplayName(),
                account.getAvatarUrl(),
                account.getLanguage(),
                account.getTimezone(),
                account.isEmailVerified());
    }
}