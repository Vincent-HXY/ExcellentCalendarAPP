-- ============================================================================
-- V2: Change user_preferences.settings from JSONB to TEXT
-- Description: The settings column was defined as JSONB but the JPA entity
-- maps it as a plain String. Changing to TEXT to avoid type mismatch.
-- ============================================================================

ALTER TABLE user_preferences ALTER COLUMN settings TYPE TEXT;