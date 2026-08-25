package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.not;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.excellentcalendar.cloud.identity.application.RegistrationService;
import com.excellentcalendar.cloud.identity.application.SessionService;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.PasswordCredentialRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAgreementAcceptanceRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserSessionRepository;
import com.excellentcalendar.cloud.platform.idempotency.IdempotencyRecordRepository;
import com.excellentcalendar.cloud.userdevice.infrastructure.persistence.UserPreferencesRepository;
import com.excellentcalendar.cloud.userdevice.infrastructure.persistence.UserProfileRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.context.WebApplicationContext;

/**
 * Security/CORS infrastructure context without a database: repositories are mocked so the api
 * profile can start while DataSource/JPA/Flyway autoconfiguration stays excluded.
 */
@ActiveProfiles("api")
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.MOCK,
        properties = "spring.autoconfigure.exclude="
                + "org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration,"
                + "org.springframework.boot.hibernate.autoconfigure.HibernateJpaAutoConfiguration,"
                + "org.springframework.boot.flyway.autoconfigure.FlywayAutoConfiguration")
class ApiInfrastructureContextTest {

    @MockitoBean
    private UserAccountRepository userAccountRepository;
    @MockitoBean
    private PasswordCredentialRepository passwordCredentialRepository;
    @MockitoBean
    private UserAgreementAcceptanceRepository userAgreementAcceptanceRepository;
    @MockitoBean
    private EmailActionChallengeRepository emailActionChallengeRepository;
    @MockitoBean
    private com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailChangeRequestRepository emailChangeRequestRepository;
    @MockitoBean
    private com.excellentcalendar.cloud.media.infrastructure.persistence.UserAvatarAssetRepository userAvatarAssetRepository;
    @MockitoBean
    private UserSessionRepository userSessionRepository;
    @MockitoBean
    private RefreshTokenGrantRepository refreshTokenGrantRepository;
    @MockitoBean
    private UserProfileRepository userProfileRepository;
    @MockitoBean
    private UserPreferencesRepository userPreferencesRepository;
    @MockitoBean
    private IdempotencyRecordRepository idempotencyRecordRepository;
    @MockitoBean
    private RegistrationService registrationService;
    @MockitoBean
    private SessionService sessionService;
    @MockitoBean
    private com.excellentcalendar.cloud.identity.application.support.PendingEmailChangeRequestPersister
            pendingEmailChangeRequestPersister;
    @MockitoBean
    private com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipalResolver principalResolver;

    @Autowired
    private WebApplicationContext applicationContext;

    @Autowired
    private tools.jackson.databind.ObjectMapper objectMapper;

    @Test
    void wireFormatUsesContractSnakeCase() throws Exception {
        String json = objectMapper.writeValueAsString(
                new com.excellentcalendar.cloud.identity.api.RegisterRequestDto(
                        "user@example.com", "calendar_user", "Calendar User", "CorrectHorseBattery",
                        "zh-CN", "Asia/Shanghai", "terms-v1", true));
        assertThat(json)
                .contains("\"agreement_accepted\"", "\"display_name\"", "\"agreement_version\"")
                .doesNotContain("\"displayName\"", "\"agreementAccepted\"");
    }

    @Test
    void wireFormatDeserializesSnakeCaseRequests() throws Exception {
        String json = """
                {"email":"user@example.com","username":"calendar_user","display_name":"Calendar User",
                 "password":"CorrectHorseBattery","locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """;
        com.excellentcalendar.cloud.identity.api.RegisterRequestDto dto =
                objectMapper.readValue(json, com.excellentcalendar.cloud.identity.api.RegisterRequestDto.class);
        assertThat(dto.email()).isEqualTo("user@example.com");
        assertThat(dto.agreementAccepted()).isTrue();
        assertThat(dto.displayName()).isEqualTo("Calendar User");
    }

    @Test
    void issuedAccessTokensVerifyRoundTrip() {
        com.excellentcalendar.cloud.platform.security.JwtIssuer issuer =
                applicationContext.getBean(com.excellentcalendar.cloud.platform.security.JwtIssuer.class);
        com.excellentcalendar.cloud.platform.security.AccessTokenVerifier verifier =
                applicationContext.getBean(com.excellentcalendar.cloud.platform.security.AccessTokenVerifier.class);

        java.util.UUID accountId = java.util.UUID.randomUUID();
        java.util.UUID sessionId = java.util.UUID.randomUUID();
        com.excellentcalendar.cloud.platform.security.JwtIssuer.IssuedAccessToken issued =
                issuer.issue(accountId, sessionId);
        org.springframework.security.oauth2.jwt.Jwt verified = verifier.verify(issued.tokenValue());
        assertThat(verified.getSubject()).isEqualTo(accountId.toString());
        assertThat(verified.getClaimAsString("sid")).isEqualTo(sessionId.toString());
    }

    @Test
    void registerRequestBindsThroughTheMvcStack() throws Exception {
        org.mockito.BDDMockito.when(idempotencyRecordRepository.insertOrTakeOverExpired(
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any()))
                .thenReturn(1);
        org.mockito.BDDMockito.when(idempotencyRecordRepository.findByScopeAndKeyHashAndExpiresAtGreaterThan(
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any()))
                .thenReturn(java.util.Optional.empty());
        org.mockito.BDDMockito.when(registrationService.register(
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any()))
                .thenReturn(new com.excellentcalendar.cloud.identity.application.AuthenticationResults.RegistrationPending(
                        java.util.UUID.randomUUID(),
                        new com.excellentcalendar.cloud.identity.application.AuthenticationResults.Challenge(
                                java.util.UUID.randomUUID(),
                                null,
                                com.excellentcalendar.cloud.identity.domain.EmailActionPurpose.registration_verification,
                                "u***r@example.com",
                                java.util.List.of("code"),
                                java.time.Instant.parse("2026-08-16T07:00:00Z"),
                                java.time.Instant.parse("2026-08-16T07:01:00Z"))));

        MockMvc mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext)
                .apply(springSecurity())
                .build();
        var result = mockMvc.perform(post("/api/v1/auth/register")
                        .header("Idempotency-Key", java.util.UUID.randomUUID().toString())
                        .contentType("application/json")
                        .content("""
                                {"email":"user@example.com","username":"calendar_user","display_name":"Calendar User",
                                 "password":"CorrectHorseBattery","locale":"zh-CN","timezone":"Asia/Shanghai",
                                 "agreement_version":"terms-v1","agreement_accepted":true}
                                """))
                .andReturn();
        assertThat(result.getResponse().getStatus())
                .as("body: %s", result.getResponse().getContentAsString())
                .isEqualTo(200);
    }

    @Test
    void apiSecurityAndCorsInfrastructureStartsWithoutFakeDatabase() {
        assertThat(applicationContext.getBeansOfType(SecurityFilterChain.class)).hasSize(1);
        assertThat(applicationContext.getBean("corsConfigurationSource"))
                .isInstanceOf(CorsConfigurationSource.class);
        assertThat(applicationContext.getBeansOfType(UserDetailsService.class)).isEmpty();
    }

    @Test
    void healthIsPublicAndUndeclaredApiRoutesRequireAuthentication() throws Exception {
        MockMvc mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext)
                .apply(springSecurity())
                .build();

        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk());
        mockMvc.perform(post("/api/v1/sync/push"))
                .andExpect(status().isUnauthorized());
        // Non-API paths stay denied for anonymous requests as well.
        mockMvc.perform(get("/not-an-api-path"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void declaredPublicAuthEndpointIsNotRejectedByTheChain() throws Exception {
        // The endpoint must reach the controller, not stop at the security layer: stub the
        // service to fail with the controller-level code and assert that code comes back.
        org.mockito.BDDMockito.when(sessionService.login(
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any(),
                        org.mockito.ArgumentMatchers.any()))
                .thenThrow(new com.excellentcalendar.cloud.platform.api.ApiException(
                        com.excellentcalendar.cloud.platform.api.ApiErrorCode.AUTH_INVALID_CREDENTIALS));
        MockMvc mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext)
                .apply(springSecurity())
                .build();

        mockMvc.perform(post("/api/v1/auth/login")
                        .contentType("application/json")
                        .content("{\"email\":\"user@example.com\",\"password\":\"secret123\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers
                        .jsonPath("$.error.code").value("AUTH_INVALID_CREDENTIALS"));
    }

    @Test
    void unmappedAndWrongMethodPathsReturnMinimalErrorsWithoutInternalLeaks() throws Exception {
        var issuer = applicationContext.getBean(
                com.excellentcalendar.cloud.platform.security.JwtIssuer.class);
        java.util.UUID accountId = java.util.UUID.randomUUID();
        java.util.UUID sessionId = java.util.UUID.randomUUID();
        org.mockito.BDDMockito.when(principalResolver.resolve(
                        org.mockito.ArgumentMatchers.eq(accountId),
                        org.mockito.ArgumentMatchers.eq(sessionId)))
                .thenReturn(new com.excellentcalendar.cloud.platform.security
                        .AuthenticatedPrincipalResolver.PrincipalResolution.Authenticated(
                        new com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipal(
                                accountId, sessionId, "user@example.com", "active",
                                java.time.Instant.now(),
                                java.time.Instant.now(),
                                java.time.Instant.now())));
        String token = issuer.issue(accountId, sessionId).tokenValue();

        MockMvc mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext)
                .apply(springSecurity())
                .build();

        // The contract declares no 404/405 error codes, so these paths keep the framework's
        // minimal error body; the server must not leak internals through it.
        var notFound = mockMvc.perform(get("/api/v1/no/such/route")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isNotFound())
                .andReturn();
        assertThat(notFound.getResponse().getContentAsString())
                .doesNotContain("Exception", "at com.excellentcalendar", "stacktrace", "Trace");

        var methodNotAllowed = mockMvc.perform(post("/api/v1/users/me")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isMethodNotAllowed())
                .andReturn();
        assertThat(methodNotAllowed.getResponse().getContentAsString())
                .doesNotContain("Exception", "at com.excellentcalendar", "stacktrace", "Trace");
    }
}
