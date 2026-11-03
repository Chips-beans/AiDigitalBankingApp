-- M5/M6: merchant payment requests and confirmed collection snapshots.
-- Additive only. The transactions table remains the authoritative ledger.

-- A fixed-amount request a shop shows as a QR. One registered DYNAMIC payment
-- row per request; its row lock serializes payment against cancellation.
CREATE TABLE merchant_payment_requests (
    id UUID PRIMARY KEY,
    merchant_id BIGINT NOT NULL REFERENCES merchants(id),
    owner_user_id BIGINT NOT NULL REFERENCES users(id),
    payment_id BIGINT NOT NULL UNIQUE REFERENCES payments(id),
    account_number VARCHAR(20) NOT NULL,
    currency VARCHAR(3) NOT NULL CHECK (currency IN ('USD','KHR')),
    amount NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    order_reference VARCHAR(50),
    reference VARCHAR(20) NOT NULL UNIQUE,
    status VARCHAR(16) NOT NULL DEFAULT 'WAITING'
        CHECK (status IN ('WAITING','PAID','EXPIRED','CANCELLED')),
    key_hash VARCHAR(64) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    transaction_id BIGINT UNIQUE REFERENCES transactions(id),
    CHECK (expires_at > created_at),
    CHECK ((status = 'PAID') = (transaction_id IS NOT NULL)),
    CHECK (status = 'WAITING' OR completed_at IS NOT NULL),
    UNIQUE (owner_user_id, key_hash)
);
CREATE INDEX idx_merchant_requests_shop ON merchant_payment_requests(merchant_id, created_at DESC);
CREATE INDEX idx_merchant_requests_waiting ON merchant_payment_requests(expires_at) WHERE status = 'WAITING';

-- Confirmed QR collections, snapshotted at payment time. Later shop edits never
-- rewrite them. Amount/currency are what the shop received; paid_* is the debit.
CREATE TABLE merchant_collections (
    transaction_id BIGINT PRIMARY KEY REFERENCES transactions(id),
    merchant_id BIGINT NOT NULL REFERENCES merchants(id),
    account_number VARCHAR(20) NOT NULL,
    currency VARCHAR(3) NOT NULL CHECK (currency IN ('USD','KHR')),
    amount NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    paid_currency VARCHAR(3) NOT NULL CHECK (paid_currency IN ('USD','KHR')),
    paid_amount NUMERIC(15,2) NOT NULL CHECK (paid_amount > 0),
    exchange_rate NUMERIC(12,4),
    reference_number VARCHAR(36) NOT NULL UNIQUE,
    payment_request_id UUID UNIQUE REFERENCES merchant_payment_requests(id),
    store_name VARCHAR(150) NOT NULL,
    payer_name VARCHAR(100) NOT NULL,
    payer_account_masked VARCHAR(24) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_merchant_collections_time ON merchant_collections(merchant_id, created_at DESC, transaction_id DESC);
CREATE INDEX idx_merchant_collections_account ON merchant_collections(account_number, created_at DESC);
