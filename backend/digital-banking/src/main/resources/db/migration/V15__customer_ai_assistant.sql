CREATE TABLE ai_conversations (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(80) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX ai_conversations_owner ON ai_conversations(user_id, updated_at DESC, id DESC);

CREATE TABLE ai_requests (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES ai_conversations(id) ON DELETE CASCADE,
    request_key VARCHAR(100) NOT NULL,
    kind VARCHAR(12) NOT NULL CHECK (kind IN ('CREATE','MESSAGE')),
    fingerprint VARCHAR(64) NOT NULL,
    status VARCHAR(12) NOT NULL CHECK (status IN ('PENDING','COMPLETED','FAILED')),
    result_json TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    UNIQUE(user_id, request_key)
);
CREATE UNIQUE INDEX ai_one_pending_turn ON ai_requests(conversation_id)
    WHERE kind='MESSAGE' AND status='PENDING';
CREATE INDEX ai_request_expiry ON ai_requests(expires_at);

CREATE TABLE ai_messages (
    id BIGSERIAL PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
    request_id UUID NOT NULL UNIQUE REFERENCES ai_requests(id) ON DELETE CASCADE,
    message VARCHAR(2000) NOT NULL,
    locale VARCHAR(2) NOT NULL CHECK (locale IN ('en','km')),
    answer_json TEXT NOT NULL,
    filters_json TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX ai_message_history ON ai_messages(conversation_id, created_at DESC, id DESC);
CREATE INDEX ai_message_expiry ON ai_messages(expires_at);

CREATE TABLE ai_usage_limits (
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    window_key VARCHAR(32) NOT NULL,
    requests INTEGER NOT NULL CHECK(requests >= 0),
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY(user_id, window_key)
);
