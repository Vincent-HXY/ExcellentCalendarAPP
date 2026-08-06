package com.excellentcalendar.cloud.userdevice.web;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.excellentcalendar.cloud.userdevice.dto.response.UserProfileResponse;
import com.excellentcalendar.cloud.userdevice.service.UserProfileService;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
class UserProfileControllerTest {

    private MockMvc mockMvc;

    @Mock
    private UserProfileService userProfileService;

    private final UUID userId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        UserProfileController controller = new UserProfileController(userProfileService);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .build();
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(
                        userId, null, List.of(new SimpleGrantedAuthority("ROLE_USER"))));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private UserProfileResponse validProfileResponse() {
        return new UserProfileResponse(userId, "Test User", "testuser", null, "en", "UTC");
    }

    @Nested
    @DisplayName("GET /api/v1/users/me")
    class GetProfile {

        @Test
        @DisplayName("should return 200 with profile")
        void shouldReturn200() throws Exception {
            when(userProfileService.getProfile(userId)).thenReturn(validProfileResponse());

            mockMvc.perform(get("/api/v1/users/me"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.displayName").value("Test User"));
        }
    }

    @Nested
    @DisplayName("PATCH /api/v1/users/me")
    class UpdateProfile {

        @Test
        @DisplayName("should return 200 with updated profile")
        void shouldReturn200() throws Exception {
            UserProfileResponse updated = new UserProfileResponse(
                    userId, "New Name", "testuser", null, "en", "UTC");
            when(userProfileService.updateProfile(eq(userId), any())).thenReturn(updated);

            mockMvc.perform(patch("/api/v1/users/me")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("""
                                    {
                                        "displayName": "New Name"
                                    }
                                    """))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.displayName").value("New Name"));
        }
    }

    @Nested
    @DisplayName("POST /api/v1/users/me/avatar")
    class UploadAvatar {

        @Test
        @DisplayName("should return 200 with updated profile")
        void shouldReturn200() throws Exception {
            UserProfileResponse updated = new UserProfileResponse(
                    userId, "Test User", "testuser", "uploads/avatars/test.jpg", "en", "UTC");
            MockMultipartFile file = new MockMultipartFile(
                    "file", "avatar.jpg", "image/jpeg", new byte[]{(byte) 0xFF, (byte) 0xD8, (byte) 0xFF});
            when(userProfileService.uploadAvatar(eq(userId), any())).thenReturn(updated);

            mockMvc.perform(multipart("/api/v1/users/me/avatar")
                            .file(file))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.avatarUrl").value("uploads/avatars/test.jpg"));
        }
    }

    @Nested
    @DisplayName("DELETE /api/v1/users/me/avatar")
    class DeleteAvatar {

        @Test
        @DisplayName("should return 200")
        void shouldReturn200() throws Exception {
            when(userProfileService.deleteAvatar(userId)).thenReturn(validProfileResponse());

            mockMvc.perform(delete("/api/v1/users/me/avatar"))
                    .andExpect(status().isOk());
        }
    }
}