-- SecureVault initial schema (Phase 1, DRAFT: subject to security review).
-- The server stores ONLY ciphertext and public metadata. It never stores
-- master passwords, plaintext vault data, or unwrapped keys.

CREATE TABLE users (
    id          UUID PRIMARY KEY,
    email       TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    disabled_at TIMESTAMPTZ
);

-- Opaque authentication material. The scheme (e.g. an augmented PAKE) is
-- not yet chosen; the master password must never be sent to the server.
CREATE TABLE auth_credentials (
    id          UUID PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    scheme      TEXT NOT NULL,
    verifier    BYTEA NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE devices (
    id          UUID PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    public_key  BYTEA NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at  TIMESTAMPTZ
);

CREATE TABLE organizations (
    id          UUID PRIMARY KEY,
    name        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE organization_members (
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role            TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'member')),
    PRIMARY KEY (organization_id, user_id)
);

CREATE TABLE vaults (
    id              UUID PRIMARY KEY,
    owner_user_id   UUID REFERENCES users(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    key_version     INTEGER NOT NULL DEFAULT 1 CHECK (key_version > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((owner_user_id IS NULL) <> (organization_id IS NULL))
);

CREATE TABLE vault_members (
    vault_id UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role     TEXT NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
    PRIMARY KEY (vault_id, user_id)
);

CREATE TABLE encrypted_items (
    id             UUID PRIMARY KEY,
    vault_id       UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    format_version SMALLINT NOT NULL,
    key_version    INTEGER NOT NULL CHECK (key_version > 0),
    ciphertext     BYTEA NOT NULL,
    revision       BIGINT NOT NULL DEFAULT 1,
    deleted_at     TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX encrypted_items_vault_idx ON encrypted_items (vault_id, updated_at);

-- Wrapped vault keys, one per (vault, member/device, key version).
CREATE TABLE vault_key_envelopes (
    id          UUID PRIMARY KEY,
    vault_id    UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_version INTEGER NOT NULL CHECK (key_version > 0),
    wrapped_key BYTEA NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (vault_id, user_id, key_version)
);

CREATE TABLE sync_operations (
    id         BIGSERIAL PRIMARY KEY,
    vault_id   UUID NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    device_id  UUID NOT NULL REFERENCES devices(id),
    item_id    UUID NOT NULL,
    operation  TEXT NOT NULL CHECK (operation IN ('put', 'delete')),
    revision   BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX sync_operations_vault_idx ON sync_operations (vault_id, id);

CREATE TABLE attachments (
    id         UUID PRIMARY KEY,
    item_id    UUID NOT NULL REFERENCES encrypted_items(id) ON DELETE CASCADE,
    object_key TEXT NOT NULL,
    size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Only a hash of the session token is stored.
CREATE TABLE sessions (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id  UUID REFERENCES devices(id) ON DELETE SET NULL,
    token_hash BYTEA NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);

-- Must never contain secrets or vault plaintext.
CREATE TABLE audit_events (
    id         BIGSERIAL PRIMARY KEY,
    user_id    UUID REFERENCES users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    metadata   JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
