CREATE TABLE account_opening_requests (
    actor_user_id BIGINT NOT NULL REFERENCES users(id),
    request_key VARCHAR(128) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    response_json TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (actor_user_id, request_key)
);

ALTER TABLE payments ADD COLUMN qr_type VARCHAR(10);
UPDATE payments SET qr_type = CASE WHEN qr_string LIKE '000201010211%' THEN 'STATIC' ELSE 'DYNAMIC' END;
ALTER TABLE payments ALTER COLUMN qr_type SET NOT NULL;
ALTER TABLE payments ADD CONSTRAINT ck_payment_qr_type CHECK (qr_type IN ('STATIC', 'DYNAMIC'));
ALTER TABLE payments ADD COLUMN transaction_id BIGINT REFERENCES transactions(id);
-- Old static payloads may differ by remark. Keep them valid, and designate the
-- oldest as the stable account QR through the generation service.
CREATE INDEX ix_payments_account_type ON payments(account_number, qr_type, id);

CREATE TABLE qr_transfer_requests (
    actor_user_id BIGINT NOT NULL REFERENCES users(id),
    request_key VARCHAR(128) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    response_json TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (actor_user_id, request_key)
);
