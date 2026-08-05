-- ============================================================================
-- V2__userdevice.sql
-- User profiles: display name, username, avatar, language, timezone.
-- Each user has exactly one profile row, keyed by the same UUID as the
-- user_accounts table in the identity module.
-- ============================================================================

CREATE TABLE user_profiles (
    user_id         UUID            PRIMARY KEY,
    display_name    VARCHAR(100)    NOT NULL,
    username        VARCHAR(50)     NOT NULL,
    avatar_path     VARCHAR(500),
    language        VARCHAR(10)     NOT NULL DEFAULT 'en',
    timezone        VARCHAR(50)     NOT NULL DEFAULT 'UTC',
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL,
    version         INTEGER         NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX uq_user_profiles_username ON user_profiles (LOWER(username));