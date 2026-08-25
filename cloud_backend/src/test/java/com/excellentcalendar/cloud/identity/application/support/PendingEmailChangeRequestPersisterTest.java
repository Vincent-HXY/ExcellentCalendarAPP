package com.excellentcalendar.cloud.identity.application.support;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.EmailChangeStatus;
import com.excellentcalendar.cloud.identity.infrastructure.IdentityProperties;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailChangeRequestEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailChangeRequestRepository;
import com.excellentcalendar.cloud.platform.time.IdGenerator;
import java.sql.SQLException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;

/**
 * The partial unique index race: when a concurrent request wins, the persister must retry once
 * and supersede the winner's row instead of surfacing a 500.
 */
class PendingEmailChangeRequestPersisterTest {

    private static final Instant NOW = Instant.parse("2026-08-17T12:00:00Z");

    @Test
    void retriesOnceWhenThePendingIndexRaceIsLost() {
        EmailActionChallengeRepository challengeRepository = mock(EmailActionChallengeRepository.class);
        EmailChangeRequestRepository requestRepository = mock(EmailChangeRequestRepository.class);
        ChallengeSupport challengeSupport = mock(ChallengeSupport.class);
        IdGenerator idGenerator = mock(IdGenerator.class);
        PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
        given(transactionManager.getTransaction(any())).willReturn(mock(TransactionStatus.class));

        UUID accountId = UUID.randomUUID();
        UUID challengeId = UUID.randomUUID();
        UUID requestId = UUID.randomUUID();
        given(idGenerator.next()).willReturn(challengeId, requestId);
        given(requestRepository.findFirstByUserIdAndStatusOrderByCreatedAtDesc(
                accountId, EmailChangeStatus.pending)).willReturn(Optional.empty());

        EmailActionChallengeEntity challenge = new EmailActionChallengeEntity(
                challengeId, accountId, EmailActionPurpose.email_change, "new@example.com",
                "hash", new IdentityProperties().getMaxAttempts(),
                NOW.plusSeconds(600), NOW.plusSeconds(60), NOW);
        given(challengeSupport.issue(accountId, EmailActionPurpose.email_change, "new@example.com"))
                .willReturn(new ChallengeSupport.IssuedChallenge(challenge, "123456"));
        given(challengeSupport.toChallengeResult(any(), any()))
                .willReturn(new AuthenticationResults.Challenge(
                        challengeId, requestId, EmailActionPurpose.email_change,
                        "n***w@example.com", List.of("code"), NOW.plusSeconds(600), NOW.plusSeconds(60)));

        DataIntegrityViolationException violation = new DataIntegrityViolationException(
                "duplicate key", new SQLException(
                        "ERROR: duplicate key value violates unique constraint \"uq_email_change_requests_pending\""));
        given(requestRepository.saveAndFlush(any(EmailChangeRequestEntity.class)))
                .willThrow(violation)
                .willAnswer(invocation -> invocation.getArgument(0));

        PendingEmailChangeRequestPersister persister = new PendingEmailChangeRequestPersister(
                challengeRepository, requestRepository, challengeSupport,
                Clock.fixed(NOW, ZoneId.of("UTC")), idGenerator, transactionManager);

        AuthenticationResults.Challenge result = persister.persist(accountId, "old@example.com", "new@example.com");

        assertThat(result.actionId()).isEqualTo(requestId);
        // Attempt 1 lost the race and rolled back; attempt 2 superseded the winner's row.
        verify(requestRepository, times(2)).saveAndFlush(any(EmailChangeRequestEntity.class));
        verify(challengeSupport, times(2)).issue(accountId, EmailActionPurpose.email_change, "new@example.com");
    }

    @Test
    void unrelatedViolationsAreNotRetried() {
        EmailActionChallengeRepository challengeRepository = mock(EmailActionChallengeRepository.class);
        EmailChangeRequestRepository requestRepository = mock(EmailChangeRequestRepository.class);
        ChallengeSupport challengeSupport = mock(ChallengeSupport.class);
        IdGenerator idGenerator = mock(IdGenerator.class);
        PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
        given(transactionManager.getTransaction(any())).willReturn(mock(TransactionStatus.class));

        given(requestRepository.findFirstByUserIdAndStatusOrderByCreatedAtDesc(any(), any()))
                .willReturn(Optional.empty());
        given(idGenerator.next()).willReturn(UUID.randomUUID());
        EmailActionChallengeEntity challenge = new EmailActionChallengeEntity(
                UUID.randomUUID(), UUID.randomUUID(), EmailActionPurpose.email_change, "new@example.com",
                "hash", 5, NOW.plusSeconds(600), NOW.plusSeconds(60), NOW);
        given(challengeSupport.issue(any(), any(), any()))
                .willReturn(new ChallengeSupport.IssuedChallenge(challenge, "123456"));
        DataIntegrityViolationException unrelated = new DataIntegrityViolationException(
                "boom", new SQLException("some other constraint"));
        given(requestRepository.saveAndFlush(any(EmailChangeRequestEntity.class)))
                .willThrow(unrelated);

        PendingEmailChangeRequestPersister persister = new PendingEmailChangeRequestPersister(
                challengeRepository, requestRepository, challengeSupport,
                Clock.fixed(NOW, ZoneId.of("UTC")), idGenerator, transactionManager);

        org.assertj.core.api.Assertions.assertThatThrownBy(() ->
                        persister.persist(UUID.randomUUID(), "old@example.com", "new@example.com"))
                .isInstanceOf(DataIntegrityViolationException.class);
        verify(requestRepository, times(1)).saveAndFlush(any(EmailChangeRequestEntity.class));
    }
}
