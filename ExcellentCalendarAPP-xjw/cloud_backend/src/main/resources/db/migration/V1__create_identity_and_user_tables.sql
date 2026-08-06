-- ============================================================================
-- V1: Core identity and user tables
-- Description: Creates the foundational tables for authentication (identity)
-- and user profile/preferences (userdevice) modules.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. user_account – the root identity record
-- ---------------------------------------------------------------------------
CREATE TABLE user_account (
    id                  UUID        NOT NULL PRIMARY KEY,
    email               TEXT        NOT NULL,
    password_hash       TEXT        NOT NULL,
    status              TEXT        NOT NULL DEFAULT 'pending_verification'
                        CONSTRAINT chk_user_account_status
                        CHECK (status IN ('pending_verification', 'active', 'disabled', 'deleted')),
    email_verified_at   TIMESTAMPTZ,
    agreement_version   TEXT        NOT NULL,
    agreement_accepted  BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_user_account_email ON user_account (lower(email));
CREATE INDEX idx_user_account_status ON user_account (status);

COMMENT ON TABLE  user_account IS 'Root identity record for every registered user.';
COMMENT ON COLUMN user_account.email IS 'Normalized to lowercase for uniqueness.';
COMMENT ON COLUMN user_account.password_hash IS 'Argon2id hash — never the raw password.';

-- ---------------------------------------------------------------------------
-- 2. user_profile – public profile fields
-- ---------------------------------------------------------------------------
CREATE TABLE user_profile (
    user_id             UUID        NOT NULL PRIMARY KEY
                        REFERENCES user_account (id)
                        ON DELETE CASCADE,
    username            TEXT        NOT NULL,
    display_name        TEXT        NOT NULL,
    avatar_asset_id     UUID,
    avatar_url          TEXT,
    avatar_thumbnail_url TEXT,
    avatar_etag         TEXT,
    avatar_updated_at   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_user_profile_username ON user_profile (lower(username));

COMMENT ON TABLE  user_profile IS 'Public profile for the authenticated user.';
COMMENT ON COLUMN user_profile.username IS 'Lowercase alphanumeric + underscore, unique.';

-- ---------------------------------------------------------------------------
-- 3. user_preferences – user locale, timezone, reminder defaults, settings
-- ---------------------------------------------------------------------------
CREATE TABLE user_preferences (
    user_id                  UUID        NOT NULL PRIMARY KEY
                             REFERENCES user_account (id)
                             ON DELETE CASCADE,
    locale                   TEXT        NOT NULL,
    timezone                 TEXT        NOT NULL,
    default_reminder_methods TEXT[]      NOT NULL DEFAULT '{}',
    settings                 JSONB       NOT NULL DEFAULT '{}',
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  user_preferences IS 'Stable user preferences returned with the current-user aggregate.';
COMMENT ON COLUMN user_preferences.default_reminder_methods IS 'Array of enum values: ring, popup, wechat.';
COMMENT ON COLUMN user_preferences.settings IS 'Flat key-value JSONB, no nested objects.';

-- ---------------------------------------------------------------------------
-- 4. verification_challenge – email verification, password reset, etc.
-- ---------------------------------------------------------------------------
CREATE TABLE verification_challenge (
    id                  UUID        NOT NULL PRIMARY KEY,
    user_id             UUID        NOT NULL
                        REFERENCES user_account (id)
                        ON DELETE CASCADE,
    purpose             TEXT        NOT NULL
                        CONSTRAINT chk_vc_purpose
                        CHECK (purpose IN ('registration_verification', 'email_change', 'password_reset')),
    masked_email        TEXT        NOT NULL,
    credential_types    TEXT[]      NOT NULL DEFAULT '{code}',
    code_hash           TEXT,
    link_token_hash     TEXT,
    expires_at          TIMESTAMPTZ NOT NULL,
    failed_attempts     INTEGER     NOT NULL DEFAULT 0,
    max_attempts        INTEGER     NOT NULL DEFAULT 5,
    consumed_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_vc_user_id ON verification_challenge (user_id);
CREATE INDEX idx_vc_purpose ON verification_challenge (purpose);
CREATE INDEX idx_vc_expires_at ON verification_challenge (expires_at);

COMMENT ON TABLE  verification_challenge IS 'One-time email challenge for verification, password reset, or email change.';
COMMENT ON COLUMN verification_challenge.code_hash IS 'SHA-256 of the 6-digit code — never store the raw code.';
COMMENT ON COLUMN verification_challenge.link_token_hash IS 'SHA-256 of the opaque link token — never store the raw token.';

-- ---------------------------------------------------------------------------
-- 5. refresh_token_grant – refresh token family for session rotation
-- ---------------------------------------------------------------------------
CREATE TABLE refresh_token_grant (
    id                  UUID        NOT NULL PRIMARY KEY,
    user_id             UUID        NOT NULL
                        REFERENCES user_account (id)
                        ON DELETE CASCADE,
    session_id          UUID        NOT NULL,
    token_hash          TEXT        NOT NULL,
    family_id           UUID        NOT NULL,
    parent_id           UUID,
    status              TEXT        NOT NULL DEFAULT 'active'
                        CONSTRAINT chk_rtg_status
                        CHECK (status IN ('active', 'consumed', 'revoked', 'expired')),
    expires_at          TIMESTAMPTZ NOT NULL,
    revoked_at          TIMESTAMPTZ,
    revocation_reason   TEXT
                        CONSTRAINT chk_rtg_reason
                        CHECK (revocation_reason IN (
                            'logout', 'logout_all', 'password_changed',
                            'password_reset', 'email_changed',
                            'refresh_token_reused', 'account_disabled', 'expired'
                        )),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rtg_user_id ON refresh_token_grant (user_id);
CREATE INDEX idx_rtg_session_id ON refresh_token_grant (session_id);
CREATE INDEX idx_rtg_family_id ON refresh_token_grant (family_id);
CREATE INDEX idx_rtg_status ON refresh_token_grant (status);
CREATE INDEX idx_rtg_expires_at ON refresh_token_grant (expires_at);

COMMENT ON TABLE  refresh_token_grant IS 'Each row represents one refresh token issuance in a rotating family.';
COMMENT ON COLUMN refresh_token_grant.token_hash IS 'SHA-256 of the refresh token — never store the raw token.';
COMMENT ON COLUMN refresh_token_grant.family_id IS 'Groups all grants from the same original token issuance.';
COMMENT ON COLUMN refresh_token_grant.parent_id IS 'Previous grant in the chain — null for root grants.';

-- ---------------------------------------------------------------------------
-- 6. email_change_request – pending email change flow
-- ---------------------------------------------------------------------------
CREATE TABLE email_change_request (
    id                  UUID        NOT NULL PRIMARY KEY,
    user_id             UUID        NOT NULL
                        REFERENCES user_account (id)
                        ON DELETE CASCADE,
    old_email           TEXT        NOT NULL,
    new_email           TEXT        NOT NULL,
    challenge_id        UUID        NOT NULL
                        REFERENCES verification_challenge (id),
    status              TEXT        NOT NULL DEFAULT 'pending'
                        CONSTRAINT chk_ecr_status
                        CHECK (status IN ('pending', 'verified', 'expired', 'cancelled')),
    expires_at          TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ecr_user_id ON email_change_request (user_id);
CREATE INDEX idx_ecr_status ON email_change_request (status);

COMMENT ON TABLE email_change_request IS 'Pending email change request. The old email remains valid until the new one is verified.';