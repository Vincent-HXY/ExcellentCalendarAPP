-- V2: email change requests (docs/domains/email_change_request).
-- At most one pending request per user; the partial unique index is the concurrency guard.

CREATE TABLE email_change_requests (
    id           uuid PRIMARY KEY,
    user_id      uuid        NOT NULL REFERENCES user_accounts (id),
    old_email    varchar(254) NOT NULL,
    new_email    varchar(254) NOT NULL,
    challenge_id uuid        NOT NULL REFERENCES email_action_challenges (id),
    status       varchar(16) NOT NULL,
    expires_at   timestamptz NOT NULL,
    completed_at timestamptz,
    created_at   timestamptz NOT NULL,
    CONSTRAINT ck_email_change_requests_status
        CHECK (status IN ('pending', 'verified', 'expired', 'cancelled'))
);

CREATE UNIQUE INDEX uq_email_change_requests_pending
    ON email_change_requests (user_id) WHERE status = 'pending';

CREATE INDEX ix_email_change_requests_user ON email_change_requests (user_id);
