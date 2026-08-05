package com.excellentcalendar.cloud.identity.web;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.excellentcalendar.cloud.identity.dto.response.ProfileResponse;
import com.excellentcalendar.cloud.identity.service.UserProfileService;
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
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(MockitoExtension.class)
class ProfileControllerTest {

    private MockMvc mockMvc;

    @Mock
    private UserProfileService userProfileService;

    private final UUID userId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        ProfileController controller = new ProfileController(userProfileService);
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

    private ProfileResponse validProfileResponse() {
        return new ProfileResponse(userId, "test@example.com", "testuser", "Test User",
                null, "en", "UTC", true);
    }

    @Nested
    @DisplayName("GET /api/v1/profile")
    class GetProfile {

        @Test
        @DisplayName("should return 200 with profile")
        void shouldReturn200() throws Exception {
            when(userProfileService.getProfile(userId)).thenReturn(validProfileResponse());

            mockMvc.perform(get("/api/v1/profile"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.email").value("test@example.com"))
                    .andExpect(jsonPath("$.displayName").value("Test User"));
        }
    }

    @Nested
    @DisplayName("PATCH /api/v1/profile")
    class UpdateProfile {

        @Test
        @DisplayName("should return 200 with updated profile")
        void shouldReturn200() throws Exception {
            ProfileResponse updated = new ProfileResponse(userId, "test@example.com", "testuser", "New Name",
                    null, "en", "UTC", true);
            when(userProfileService.updateProfile(eq(userId), any())).thenReturn(updated);

            mockMvc.perform(patch("/api/v1/profile")
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
    @DisplayName("PUT /api/v1/profile/avatar")
    class UpdateAvatar {

        @Test
        @DisplayName("should return 200 with updated profile")
        void shouldReturn200() throws Exception {
            String avatarUrl = "https://example.com/avatar.jpg";
            ProfileResponse updated = new ProfileResponse(userId, "test@example.com", "testuser", "Test User",
                    avatarUrl, "en", "UTC", true);
            when(userProfileService.updateAvatar(userId, avatarUrl)).thenReturn(updated);

            mockMvc.perform(put("/api/v1/profile/avatar")
                            .param("avatarUrl", avatarUrl))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.avatarUrl").value(avatarUrl));
        }
    }

    @Nested
    @DisplayName("DELETE /api/v1/profile/avatar")
    class DeleteAvatar {

        @Test
        @DisplayName("should return 200")
        void shouldReturn200() throws Exception {
            when(userProfileService.getProfile(userId)).thenReturn(validProfileResponse());

            mockMvc.perform(delete("/api/v1/profile/avatar"))
                    .andExpect(status().isOk());
        }
    }
}