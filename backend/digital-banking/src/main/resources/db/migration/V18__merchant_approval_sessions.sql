-- Existing sessions remain Customer sessions. Applied V1-V17 are immutable.
ALTER TABLE auth_sessions ADD COLUMN purpose VARCHAR(16) NOT NULL DEFAULT 'CUSTOMER';
ALTER TABLE auth_sessions ADD COLUMN client_id VARCHAR(80) NOT NULL DEFAULT 'kesor-customer';
ALTER TABLE auth_sessions ADD CONSTRAINT ck_auth_session_purpose CHECK
    ((purpose='CUSTOMER' AND client_id='kesor-customer') OR
     (purpose='MERCHANT' AND client_id='kesor-merchant-android'));
CREATE INDEX idx_auth_session_owner_purpose ON auth_sessions(user_id,purpose);
-- Session replacement is application-specific, including when an installation
-- fingerprint happens to match across clients. Existing uniqueness is preserved
-- within the backfilled CUSTOMER scope.
DROP INDEX uq_sessions_current_device;
CREATE UNIQUE INDEX uq_sessions_current_device ON auth_sessions(user_id,device_id,purpose,client_id)
    WHERE revoked_at IS NULL;

CREATE TABLE merchant_auth_attempts (
    id UUID PRIMARY KEY,
    client_id VARCHAR(80) NOT NULL CHECK (client_id='kesor-merchant-android'),
    redirect_uri VARCHAR(500) NOT NULL,
    state VARCHAR(128) NOT NULL,
    challenge VARCHAR(43) NOT NULL,
    secret_hash VARCHAR(64) NOT NULL,
    handoff_hash VARCHAR(64) NOT NULL,
    installation_hash VARCHAR(64) NOT NULL,
    device_name VARCHAR(100) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING','APPROVED','CONSUMED','DENIED','CANCELLED','EXPIRED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    approved_by BIGINT REFERENCES users(id),
    approved_session_id UUID REFERENCES auth_sessions(id),
    code_hash VARCHAR(64),
    exchange_hash VARCHAR(64),
    session_id UUID UNIQUE REFERENCES auth_sessions(id),
    recovery_ciphertext TEXT,
    recovery_expires_at TIMESTAMPTZ,
    CHECK (expires_at > created_at),
    CHECK (status NOT IN ('APPROVED','CONSUMED') OR
        (approved_by IS NOT NULL AND approved_session_id IS NOT NULL AND code_hash IS NOT NULL)),
    CHECK (status <> 'CONSUMED' OR (session_id IS NOT NULL AND exchange_hash IS NOT NULL))
);
CREATE INDEX idx_merchant_attempt_expiry ON merchant_auth_attempts(expires_at);
CREATE TABLE merchant_auth_limits (
    id VARCHAR(80) PRIMARY KEY,
    window_start TIMESTAMPTZ NOT NULL,
    hits INTEGER NOT NULL CHECK(hits > 0)
);
CREATE INDEX idx_merchant_limits_expiry ON merchant_auth_limits(window_start);
