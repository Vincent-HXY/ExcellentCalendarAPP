-- V1: identity and user profile schema (auth register/verify/login/session, password, idempotency)
-- Maps docs/domains/ user_account, password_credential, user_profile, user_preferences,
-- user_session, refresh_token_grant, email_action_challenge, user_agreement_acceptance.

CREATE TABLE user_accounts (
    id                 uuid PRIMARY KEY,
    email              varchar(254) NOT NULL,
    normalized_email   varchar(254) NOT NULL,
    status             varchar(32)  NOT NULL,
    email_verified_at  timestamptz,
    disabled_at        timestamptz,
    created_at         timestamptz  NOT NULL,
    updated_at         timestamptz  NOT NULL,
    deleted_at         timestamptz,
    CONSTRAINT ck_user_accounts_status
        CHECK (status IN ('pending_verification', 'active', 'disabled', 'deleted'))
);

CREATE UNIQUE INDEX uq_user_accounts_normalized_email
    ON user_accounts (normalized_email) WHERE deleted_at IS NULL;

CREATE TABLE password_credentials (
    user_id             uuid PRIMARY KEY REFERENCES user_accounts (id),
    password_hash       varchar(512) NOT NULL,
    algorithm           varchar(32)  NOT NULL,
    password_changed_at timestamptz  NOT NULL
);

CREATE TABLE user_profiles (
    user_id             uuid PRIMARY KEY REFERENCES user_accounts (id),
    username            varchar(24) NOT NULL,
    normalized_username varchar(24) NOT NULL,
    display_name        varchar(40) NOT NULL,
    avatar_asset_id     uuid,
    created_at          timestamptz NOT NULL,
    updated_at          timestamptz NOT NULL
);

-- Profile follows the account lifecycle; no account deletion endpoint exists in this phase, so the
-- username release strategy on account deletion is deferred to the deletion capability.
CREATE UNIQUE INDEX uq_user_profiles_normalized_username
    ON user_profiles (normalized_username);

CREATE TABLE user_preferences (
    user_id                  uuid PRIMARY KEY REFERENCES user_accounts (id),
    locale                   varchar(35) NOT NULL,
    timezone                 varchar(64) NOT NULL,
    default_reminder_methods text[]      NOT NULL,
    settings                 jsonb       NOT NULL,
    created_at               timestamptz NOT NULL,
    updated_at               timestamptz NOT NULL
);

CREATE TABLE user_sessions (
    id                 uuid PRIMARY KEY,
    user_id            uuid        NOT NULL REFERENCES user_accounts (id),
    token_family_id    uuid        NOT NULL,
    platform           varchar(32) NOT NULL,
    device_name        varchar(128),
    app_version        varchar(64),
    expires_at         timestamptz NOT NULL,
    last_used_at       timestamptz NOT NULL,
    revoked_at         timestamptz,
    revocation_reason  varchar(32),
    created_at         timestamptz NOT NULL,
    CONSTRAINT uq_user_sessions_token_family UNIQUE (token_family_id),
    CONSTRAINT ck_user_sessions_revocation_reason CHECK (revocation_reason IN (
        'logout', 'logout_all', 'password_changed', 'password_reset', 'email_changed',
        'refresh_token_reused', 'account_disabled', 'expired'))
);

CREATE INDEX ix_user_sessions_user ON user_sessions (user_id);
CREATE INDEX ix_user_sessions_active ON user_sessions (user_id) WHERE revoked_at IS NULL;

CREATE TABLE refresh_token_grants (
    id              uuid PRIMARY KEY,
    session_id      uuid        NOT NULL REFERENCES user_sessions (id),
    token_hash      varchar(64)    NOT NULL,
    parent_grant_id uuid REFERENCES refresh_token_grants (id),
    issued_at       timestamptz NOT NULL,
    expires_at      timestamptz NOT NULL,
    consumed_at     timestamptz,
    revoked_at      timestamptz,
    CONSTRAINT uq_refresh_token_grants_token_hash UNIQUE (token_hash)
);

CREATE INDEX ix_refresh_token_grants_session ON refresh_token_grants (session_id);

CREATE TABLE email_action_challenges (
    id                   uuid PRIMARY KEY,
    user_id              uuid        NOT NULL REFERENCES user_accounts (id),
    purpose              varchar(32) NOT NULL,
    target_email         varchar(254) NOT NULL,
    code_hash            varchar(64),
    link_token_hash      varchar(64),
    failed_attempt_count integer     NOT NULL,
    max_attempts         integer     NOT NULL,
    expires_at           timestamptz NOT NULL,
    resend_available_at  timestamptz NOT NULL,
    consumed_at          timestamptz,
    invalidated_at       timestamptz,
    created_at           timestamptz NOT NULL,
    CONSTRAINT ck_email_action_challenges_purpose
        CHECK (purpose IN ('registration_verification', 'email_change', 'password_reset'))
);

CREATE INDEX ix_email_action_challenges_user_purpose
    ON email_action_challenges (user_id, purpose);

CREATE TABLE user_agreement_acceptances (
    id                uuid PRIMARY KEY,
    user_id           uuid        NOT NULL REFERENCES user_accounts (id),
    agreement_version varchar(64) NOT NULL,
    accepted_at       timestamptz NOT NULL
);

CREATE INDEX ix_user_agreement_acceptances_user ON user_agreement_acceptances (user_id);

CREATE TABLE idempotency_records (
    id              uuid PRIMARY KEY,
    scope           varchar(96) NOT NULL,
    key_hash        varchar(64)    NOT NULL,
    request_digest  varchar(64),
    response_status integer,
    response_body   bytea,
    created_at      timestamptz NOT NULL,
    expires_at      timestamptz NOT NULL,
    CONSTRAINT uq_idempotency_records_scope_key UNIQUE (scope, key_hash)
);

CREATE INDEX ix_idempotency_records_expires ON idempotency_records (expires_at);
