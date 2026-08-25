package com.excellentcalendar.cloud.identity.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.excellentcalendar.cloud.identity.application.support.AuthenticationAssembler;
import com.excellentcalendar.cloud.identity.application.support.ChallengeSupport;
import com.excellentcalendar.cloud.identity.application.support.SessionIssuer;
import com.excellentcalendar.cloud.identity.application.support.TimingEqualizer;
import com.excellentcalendar.cloud.identity.domain.PasswordHasher;
import com.excellentcalendar.cloud.identity.domain.RateLimiter;
import com.excellentcalendar.cloud.identity.domain.UserAccountStatus;
import com.excellentcalendar.cloud.identity.infrastructure.IdentityProperties;
import com.excellentcalendar.cloud.identity.infrastructure.RateLimitProperties;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.PasswordCredentialRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserSessionRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * The unknown-email branch of password-reset request must burn a dummy Argon2 match so response
 * timing does not reveal whether an email is registered (mirrors the login path).
 */
class PasswordServiceTimingEqualizationTest {

    private static final Instant NOW = Instant.parse("2026-08-17T12:00:00Z");

    @Test
    void unknownEmailBurnsADummyHashMatchAndSendsNoMail() {
        UserAccountRepository accountRepository = mock(UserAccountRepository.class);
        TimingEqualizer timingEqualizer = mock(TimingEqualizer.class);
        ChallengeSupport challengeSupport = mock(ChallengeSupport.class);
        RateLimiter rateLimiter = mock(RateLimiter.class);
        given(rateLimiter.tryAcquire(any(), any())).willReturn(new RateLimiter.Result(true, 0));
        given(accountRepository.findByNormalizedEmail("nobody@example.com"))
                .willReturn(Optional.empty());

        PasswordService service = service(accountRepository, challengeSupport, rateLimiter, timingEqualizer);

        AuthenticationResults.PasswordResetDispatch result =
                service.requestReset("127.0.0.1", "nobody@example.com");

        assertThat(result.resendAvailableAt()).isEqualTo(NOW.plusSeconds(60));
        verify(timingEqualizer).burn("nobody@example.com");
        verify(challengeSupport, never()).issue(any(), any(), any());
    }

    @Test
    void knownEmailIssuesAChallengeWithoutBurning() {
        UserAccountRepository accountRepository = mock(UserAccountRepository.class);
        TimingEqualizer timingEqualizer = mock(TimingEqualizer.class);
        ChallengeSupport challengeSupport = mock(ChallengeSupport.class);
        RateLimiter rateLimiter = mock(RateLimiter.class);
        given(rateLimiter.tryAcquire(any(), any())).willReturn(new RateLimiter.Result(true, 0));
        UserAccountEntity account = mock(UserAccountEntity.class);
        given(account.getId()).willReturn(UUID.randomUUID());
        given(account.getStatus()).willReturn(UserAccountStatus.active);
        given(account.getEmail()).willReturn("known@example.com");
        given(accountRepository.findByNormalizedEmail("known@example.com"))
                .willReturn(Optional.of(account));

        PasswordService service = service(accountRepository, challengeSupport, rateLimiter, timingEqualizer);

        service.requestReset("127.0.0.1", "known@example.com");

        verify(challengeSupport).issue(
                account.getId(), com.excellentcalendar.cloud.identity.domain.EmailActionPurpose.password_reset,
                "known@example.com");
        verify(timingEqualizer, never()).burn(any());
    }

    private static PasswordService service(
            UserAccountRepository accountRepository,
            ChallengeSupport challengeSupport,
            RateLimiter rateLimiter,
            TimingEqualizer timingEqualizer) {
        return new PasswordService(
                accountRepository,
                mock(PasswordCredentialRepository.class),
                mock(EmailActionChallengeRepository.class),
                mock(UserSessionRepository.class),
                mock(RefreshTokenGrantRepository.class),
                challengeSupport,
                mock(SessionIssuer.class),
                mock(AuthenticationAssembler.class),
                mock(PasswordHasher.class),
                timingEqualizer,
                rateLimiter,
                new RateLimitProperties(),
                new IdentityProperties(),
                Clock.fixed(NOW, ZoneId.of("UTC")));
    }
}
