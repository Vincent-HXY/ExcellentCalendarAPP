-- V3: avatar assets (docs/domains/user_avatar_asset) and the profile pointer.
-- Immutable square assets; deletion is soft and the profile pointer is cleared by the use case.

CREATE TABLE user_avatar_assets (
    id          uuid PRIMARY KEY,
    user_id     uuid        NOT NULL REFERENCES user_accounts (id),
    storage_key varchar(256) NOT NULL,
    mime_type   varchar(32) NOT NULL,
    size_bytes  bigint      NOT NULL,
    width       integer     NOT NULL,
    height      integer     NOT NULL,
    etag        varchar(256) NOT NULL,
    created_at  timestamptz NOT NULL,
    deleted_at  timestamptz,
    CONSTRAINT uq_user_avatar_assets_storage_key UNIQUE (storage_key),
    CONSTRAINT ck_user_avatar_assets_mime CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
    CONSTRAINT ck_user_avatar_assets_size CHECK (size_bytes <= 5242880),
    CONSTRAINT ck_user_avatar_assets_square CHECK (height = width AND width > 0)
);

CREATE INDEX ix_user_avatar_assets_user ON user_avatar_assets (user_id);

ALTER TABLE user_profiles
    ADD CONSTRAINT fk_user_profiles_avatar_asset
        FOREIGN KEY (avatar_asset_id) REFERENCES user_avatar_assets (id);
