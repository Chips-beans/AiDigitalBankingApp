-- Existing customers remain complete; new continuation profiles opt into onboarding.
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;
ALTER TABLE users ADD COLUMN profile_complete BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN telegram_subject VARCHAR(128);
CREATE UNIQUE INDEX uq_users_telegram_subject ON users(telegram_subject) WHERE telegram_subject IS NOT NULL;
ALTER TABLE otp_verifications ALTER COLUMN purpose TYPE VARCHAR(32);
ALTER TABLE otp_rate_limits ALTER COLUMN id TYPE VARCHAR(160);

CREATE TABLE telegram_login_flows (
    id VARCHAR(64) PRIMARY KEY,
    exchange_secret_hash VARCHAR(64) NOT NULL,
    approval_receipt_hash VARCHAR(64),
    verifier VARCHAR(128) NOT NULL,
    nonce VARCHAR(64) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    callback_handled BOOLEAN NOT NULL DEFAULT FALSE,
    claimed BOOLEAN NOT NULL DEFAULT FALSE,
    subject VARCHAR(128),
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    error_code VARCHAR(40),
    linked_user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    linked_session_id UUID REFERENCES auth_sessions(id) ON DELETE CASCADE,
    device_fingerprint VARCHAR(255) NOT NULL,
    device_name VARCHAR(100) NOT NULL,
    device_type VARCHAR(50),
    ip_address VARCHAR(255)
);
CREATE INDEX idx_telegram_flow_expiry ON telegram_login_flows(expires_at);
