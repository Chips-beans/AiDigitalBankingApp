-- Legacy OTPs and JWTs cannot be reused after the new session policy is enabled.
ALTER TABLE otp_verifications ALTER COLUMN otp_code TYPE VARCHAR(100);
ALTER TABLE otp_verifications ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;
UPDATE otp_verifications SET verified = TRUE WHERE LENGTH(otp_code) < 20;
CREATE INDEX idx_otp_email_purpose_created ON otp_verifications(email, purpose, created_at DESC, id DESC);

CREATE TABLE otp_rate_limits (
    id VARCHAR(130) PRIMARY KEY,
    window_started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    last_requested_at TIMESTAMP WITH TIME ZONE
);

ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_device_fingerprint_key;
ALTER TABLE devices ADD CONSTRAINT uq_devices_user_fingerprint UNIQUE (user_id, device_fingerprint);

CREATE TABLE auth_sessions (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX idx_sessions_user_device ON auth_sessions(user_id, device_id);
CREATE INDEX idx_sessions_expiry ON auth_sessions(expires_at);

-- Complete the previously entity-only payments schema so schema validation can run.
CREATE TABLE IF NOT EXISTS payments (
    id BIGSERIAL PRIMARY KEY,
    md5_hash VARCHAR(255) NOT NULL UNIQUE,
    account_number VARCHAR(255) NOT NULL,
    amount NUMERIC(19,2) NOT NULL,
    currency VARCHAR(3) NOT NULL,
    status VARCHAR(255) NOT NULL,
    qr_string TEXT,
    created_at TIMESTAMP WITHOUT TIME ZONE,
    updated_at TIMESTAMP WITHOUT TIME ZONE
);
