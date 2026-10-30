-- Migration V17: fixed-rate cross-currency transfers and one-time transfer PIN proofs.
-- Existing rows are unchanged: NULL credit columns mean the destination was credited
-- the same amount and currency as the debit.
ALTER TABLE transactions ADD COLUMN credit_amount NUMERIC(15,2);
ALTER TABLE transactions ADD COLUMN credit_currency VARCHAR(3);
ALTER TABLE transactions ADD COLUMN exchange_rate NUMERIC(12,4);
ALTER TABLE transactions ADD CONSTRAINT ck_transactions_conversion CHECK (
    (credit_amount IS NULL AND credit_currency IS NULL AND exchange_rate IS NULL)
    OR (credit_amount IS NOT NULL AND credit_currency IS NOT NULL AND exchange_rate IS NOT NULL
        AND credit_amount > 0 AND credit_amount <> 'NaN'::numeric
        AND exchange_rate > 0 AND exchange_rate <> 'NaN'::numeric
        AND credit_currency IN ('USD', 'KHR') AND credit_currency <> currency));

-- A proof is issued after a correct PIN and consumed by exactly one new transfer.
CREATE TABLE transfer_pin_proofs (
    proof_hash VARCHAR(64) PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES auth_sessions(id) ON DELETE CASCADE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_transfer_pin_proofs_expiry ON transfer_pin_proofs(expires_at);
