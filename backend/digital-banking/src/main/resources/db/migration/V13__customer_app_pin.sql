CREATE TABLE customer_app_pins (
    user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    pin_hash VARCHAR(100) NOT NULL,
    failed_attempts INTEGER NOT NULL DEFAULT 0 CHECK (failed_attempts BETWEEN 0 AND 5),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- The persisted app credential can only obtain tokens after server PIN verification.
CREATE TABLE app_pin_locks (
    session_id UUID PRIMARY KEY REFERENCES auth_sessions(id) ON DELETE CASCADE,
    ticket_hash VARCHAR(64) NOT NULL UNIQUE,
    locked BOOLEAN NOT NULL DEFAULT TRUE,
    pin_generation INTEGER NOT NULL DEFAULT 0 CHECK (pin_generation >= 0),
    recovery_allowed BOOLEAN NOT NULL DEFAULT FALSE
);
