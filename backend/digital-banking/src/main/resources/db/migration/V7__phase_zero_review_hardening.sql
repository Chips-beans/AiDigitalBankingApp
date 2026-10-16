CREATE TABLE login_attempt_limits (
    id VARCHAR(128) PRIMARY KEY,
    window_started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0)
);

-- PostgreSQL does not automatically index the referencing side of foreign keys.
CREATE INDEX idx_accounts_user ON accounts(user_id);

-- Retain legacy email spelling while making identity lookup and uniqueness case-insensitive.
CREATE UNIQUE INDEX uq_users_email_normalized ON users(LOWER(email));

-- Enforce the session replacement policy and avoid scanning revoked history.
CREATE UNIQUE INDEX uq_sessions_current_device ON auth_sessions(user_id, device_id)
    WHERE revoked_at IS NULL;

-- The serialized insertion order is authoritative across servers with clock skew.
DROP INDEX idx_otp_email_purpose_created;
CREATE INDEX idx_otp_email_purpose_id ON otp_verifications(email, purpose, id DESC);
