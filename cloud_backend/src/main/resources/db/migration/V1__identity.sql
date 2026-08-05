-- ============================================================================
-- V1__identity.sql
-- Foundation: user accounts, refresh tokens, email verification, password
-- reset, and email change requests.
-- ============================================================================

-- --------------------------------------------------------------------------
-- 1. user_accounts
-- --------------------------------------------------------------------------
CREATE TABLE user_accounts (
    id                  UUID            PRIMARY KEY,
    email               VARCHAR(255)    NOT NULL,
    username            VARCHAR(50)     NOT NULL,
    display_name        VARCHAR(100)    NOT NULL,
    password_hash       VARCHAR(255)    NOT NULL,
    avatar_url          VARCHAR(500),
    email_verified_at   TIMESTAMP WITH TIME ZONE,
    language            VARCHAR(10)     NOT NULL DEFAULT 'en',
    timezone            VARCHAR(50)     NOT NULL DEFAULT 'UTC',
    enabled             BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    version             INTEGER         NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX uq_user_accounts_email ON user_accounts (LOWER(email));
CREATE UNIQUE INDEX uq_user_accounts_username ON user_accounts (LOWER(username));

-- --------------------------------------------------------------------------
-- 2. refresh_tokens
-- --------------------------------------------------------------------------
CREATE TABLE refresh_tokens (
    id                  UUID            PRIMARY KEY,
    user_account_id     UUID            NOT NULL REFERENCES user_accounts(id),
    token_hash          VARCHAR(255)    NOT NULL,
    device_info         VARCHAR(500),
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens (user_account_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens (expires_at);

-- --------------------------------------------------------------------------
-- 3. email_verification_codes
-- --------------------------------------------------------------------------
CREATE TABLE email_verification_codes (
    id                  UUID            PRIMARY KEY,
    user_account_id     UUID            NOT NULL REFERENCES user_accounts(id),
    email               VARCHAR(255)    NOT NULL,
    code                VARCHAR(10)     NOT NULL,
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    verified_at         TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_email_verification_user ON email_verification_codes (user_account_id);
CREATE INDEX idx_email_verification_code ON email_verification_codes (code);

-- --------------------------------------------------------------------------
-- 4. password_reset_tokens
-- --------------------------------------------------------------------------
CREATE TABLE password_reset_tokens (
    id                  UUID            PRIMARY KEY,
    user_account_id     UUID            NOT NULL REFERENCES user_accounts(id),
    token_hash          VARCHAR(255)    NOT NULL,
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at             TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_password_reset_user ON password_reset_tokens (user_account_id);

-- --------------------------------------------------------------------------
-- 5. email_change_requests
-- --------------------------------------------------------------------------
CREATE TABLE email_change_requests (
    id                  UUID            PRIMARY KEY,
    user_account_id     UUID            NOT NULL REFERENCES user_accounts(id),
    new_email           VARCHAR(255)    NOT NULL,
    code                VARCHAR(10)     NOT NULL,
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    verified_at         TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_email_change_user ON email_change_requests (user_account_id);