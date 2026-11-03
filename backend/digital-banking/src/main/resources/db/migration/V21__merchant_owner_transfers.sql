-- M8: owner transfers (a shop's business wallet to the same owner's personal wallet).
-- Additive only. The transactions table remains the authoritative ledger; this table is the
-- approval intent. Approval executes the posting in one database transaction, so an intent is
-- COMPLETED if and only if it references its one transaction.
CREATE TABLE merchant_owner_transfers (
    id UUID PRIMARY KEY,
    merchant_id BIGINT NOT NULL REFERENCES merchants(id),
    owner_user_id BIGINT NOT NULL REFERENCES users(id),
    source_account_number VARCHAR(20) NOT NULL,
    destination_account_number VARCHAR(20) NOT NULL,
    currency VARCHAR(3) NOT NULL CHECK (currency IN ('USD','KHR')),
    amount NUMERIC(15,2) NOT NULL CHECK (amount > 0 AND (currency <> 'KHR' OR amount = trunc(amount))),
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING','COMPLETED','DENIED','CANCELLED','EXPIRED','FAILED')),
    failure_code VARCHAR(40),
    key_hash VARCHAR(64) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    intent_hash VARCHAR(64) NOT NULL,
    handoff_hash VARCHAR(64) NOT NULL,
    state VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    transaction_id BIGINT UNIQUE REFERENCES transactions(id),
    CHECK (source_account_number <> destination_account_number),
    CHECK (expires_at > created_at),
    CHECK ((status = 'COMPLETED') = (transaction_id IS NOT NULL)),
    CHECK (status = 'PENDING' OR completed_at IS NOT NULL),
    CHECK ((status = 'FAILED') = (failure_code IS NOT NULL)),
    UNIQUE (owner_user_id, key_hash)
);
CREATE INDEX idx_merchant_owner_transfers_shop ON merchant_owner_transfers(merchant_id, created_at DESC);
-- One open intent per owner keeps approval unambiguous; lapsed rows are settled before a new one.
CREATE UNIQUE INDEX uq_merchant_owner_transfers_pending ON merchant_owner_transfers(owner_user_id) WHERE status = 'PENDING';
