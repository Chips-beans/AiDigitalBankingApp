-- Fail before adding constraints if legacy records need explicit reconciliation.
-- Never silently change existing balances, currencies, or financial history.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM accounts WHERE balance < 0 OR currency NOT IN ('USD','KHR')
               OR (currency = 'KHR' AND balance <> trunc(balance)))
       OR EXISTS (SELECT 1 FROM transactions WHERE amount <= 0 OR fee < 0
                  OR currency NOT IN ('USD','KHR')
                  OR (currency = 'KHR' AND (amount <> trunc(amount) OR fee <> trunc(fee)))) THEN
        RAISE EXCEPTION 'Financial preflight failed: reconcile invalid account balances or transaction amounts/currencies before V8';
    END IF;
END $$;

ALTER TABLE accounts ADD CONSTRAINT ck_accounts_money CHECK (
    balance >= 0 AND currency IN ('USD','KHR') AND (currency <> 'KHR' OR balance = trunc(balance)));
ALTER TABLE transactions ADD CONSTRAINT ck_transactions_money CHECK (
    amount > 0 AND fee >= 0 AND currency IN ('USD','KHR')
    AND (currency <> 'KHR' OR (amount = trunc(amount) AND fee = trunc(fee))));

ALTER TABLE audit_logs ADD COLUMN correlation_id VARCHAR(36);
CREATE INDEX idx_audit_correlation ON audit_logs(correlation_id);
ALTER TABLE transactions ADD COLUMN initiated_by_user_id BIGINT REFERENCES users(id);
ALTER TABLE transactions ADD COLUMN operation VARCHAR(40);
ALTER TABLE transactions ADD COLUMN correlation_id VARCHAR(36);

CREATE TABLE idempotency_records (
    id BIGSERIAL PRIMARY KEY,
    actor_user_id BIGINT NOT NULL REFERENCES users(id),
    operation VARCHAR(40) NOT NULL,
    request_key VARCHAR(128) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    transaction_id BIGINT UNIQUE REFERENCES transactions(id),
    response_json TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_idempotency_actor_operation_key UNIQUE(actor_user_id, operation, request_key),
    CONSTRAINT ck_idempotency_result CHECK ((transaction_id IS NULL) = (response_json IS NULL))
);
CREATE INDEX idx_transactions_account_history_source ON transactions(source_account_id, created_at DESC, id DESC);
CREATE INDEX idx_transactions_account_history_dest ON transactions(destination_account_id, created_at DESC, id DESC);
