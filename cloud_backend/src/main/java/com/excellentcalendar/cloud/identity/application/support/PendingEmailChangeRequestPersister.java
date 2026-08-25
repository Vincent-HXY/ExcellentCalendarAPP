package com.excellentcalendar.cloud.identity.application.support;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.EmailChangeStatus;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailActionChallengeRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailChangeRequestEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.EmailChangeRequestRepository;
import com.excellentcalendar.cloud.platform.time.IdGenerator;
import java.time.Clock;
import java.util.UUID;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Persists a pending email-change request in its own transaction, superseding any previous
 * pending request. Two concurrent requests race on the partial unique index
 * {@code uq_email_change_requests_pending}: the loser's flush raises a violation, rolls this
 * transaction back and retries once — now seeing the winner's row and superseding it, so the
 * "latest request wins" semantic holds without a 500.
 */
@Component
public class PendingEmailChangeRequestPersister {

    private static final int MAX_ATTEMPTS = 2;

    private final EmailActionChallengeRepository challengeRepository;
    private final EmailChangeRequestRepository requestRepository;
    private final ChallengeSupport challengeSupport;
    private final Clock clock;
    private final IdGenerator idGenerator;
    private final TransactionTemplate template;

    public PendingEmailChangeRequestPersister(
            EmailActionChallengeRepository challengeRepository,
            EmailChangeRequestRepository requestRepository,
            ChallengeSupport challengeSupport,
            Clock clock,
            IdGenerator idGenerator,
            PlatformTransactionManager transactionManager) {
        this.challengeRepository = challengeRepository;
        this.requestRepository = requestRepository;
        this.challengeSupport = challengeSupport;
        this.clock = clock;
        this.idGenerator = idGenerator;
        this.template = new TransactionTemplate(transactionManager);
        this.template.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public AuthenticationResults.Challenge persist(UUID accountId, String currentEmail, String newEmail) {
        for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
            try {
                return template.execute(status -> doPersist(accountId, currentEmail, newEmail));
            } catch (DataIntegrityViolationException exception) {
                if (attempt == MAX_ATTEMPTS - 1 || !isPendingRequestViolation(exception)) {
                    throw exception;
                }
                // A concurrent request won this round: retry, superseding its row.
            }
        }
        throw new IllegalStateException("unreachable");
    }

    private AuthenticationResults.Challenge doPersist(UUID accountId, String currentEmail, String newEmail) {
        requestRepository.findFirstByUserIdAndStatusOrderByCreatedAtDesc(
                        accountId, EmailChangeStatus.pending)
                .ifPresent(previous -> {
                    previous.cancel(clock.instant());
                    requestRepository.save(previous);
                    challengeRepository.findWithLockingById(previous.getChallengeId())
                            .ifPresent(challenge -> challenge.invalidate(clock.instant()));
                });

        ChallengeSupport.IssuedChallenge issued =
                challengeSupport.issue(accountId, EmailActionPurpose.email_change, newEmail);
        EmailChangeRequestEntity request = new EmailChangeRequestEntity(
                idGenerator.next(),
                accountId,
                currentEmail,
                newEmail,
                issued.entity().getId(),
                issued.entity().getExpiresAt(),
                clock.instant());
        requestRepository.saveAndFlush(request);
        return challengeSupport.toChallengeResult(issued.entity(), request.getId());
    }

    private static boolean isPendingRequestViolation(DataIntegrityViolationException exception) {
        return String.valueOf(exception.getMostSpecificCause().getMessage())
                .contains("uq_email_change_requests_pending");
    }
}
