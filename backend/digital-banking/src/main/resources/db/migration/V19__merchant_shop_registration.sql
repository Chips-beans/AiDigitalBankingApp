-- M4 self-service shop onboarding. Additive only: legacy shops, accounts and
-- balances are preserved. Applied V1-V18 are immutable.

-- Preflight: never repair conflicting legacy data automatically.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM accounts WHERE account_category='MERCHANT' AND merchant_id IS NOT NULL
               GROUP BY merchant_id, currency HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'V19 preflight: duplicate merchant wallets per currency must be resolved by support first';
    END IF;
END $$;

ALTER TABLE merchants
    ADD COLUMN onboarding VARCHAR(16) NOT NULL DEFAULT 'LEGACY',
    ADD COLUMN category_code VARCHAR(32),
    ADD COLUMN business_phone VARCHAR(16),
    ADD COLUMN address VARCHAR(255),
    ADD COLUMN description VARCHAR(500),
    ADD COLUMN profile_version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE merchants ADD CONSTRAINT ck_merchant_onboarding CHECK (onboarding IN ('LEGACY','SELF_SERVICE'));
ALTER TABLE merchants ADD CONSTRAINT ck_merchant_self_service_profile CHECK
    (onboarding='LEGACY' OR (category_code IS NOT NULL AND business_phone IS NOT NULL AND address IS NOT NULL));

-- One self-service shop per owner; existing legacy multi-shop owners are untouched
-- and surface as RECOVERY_REQUIRED instead of being collapsed or reassigned.
CREATE UNIQUE INDEX uq_merchants_self_service_owner ON merchants(owner_user_id) WHERE onboarding='SELF_SERVICE';
-- Exactly one business wallet per shop and currency. Personal (user_id,currency)
-- uniqueness is deliberately not added: legacy personal duplicates exist.
CREATE UNIQUE INDEX uq_accounts_merchant_currency ON accounts(merchant_id, currency)
    WHERE account_category='MERCHANT' AND merchant_id IS NOT NULL;

-- Normalized, owner-scoped logos. Staged uploads attach through registration or
-- a profile update; abandoned staged rows are swept after retention.
CREATE TABLE merchant_logos (
    id UUID PRIMARY KEY,
    owner_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    merchant_id BIGINT REFERENCES merchants(id) ON DELETE CASCADE,
    content_type VARCHAR(16) NOT NULL CHECK (content_type IN ('image/jpeg','image/png')),
    image_data BYTEA NOT NULL CHECK (octet_length(image_data) BETWEEN 1 AND 5242880),
    width INTEGER NOT NULL CHECK (width BETWEEN 1 AND 1024),
    height INTEGER NOT NULL CHECK (height BETWEEN 1 AND 1024),
    status VARCHAR(16) NOT NULL DEFAULT 'STAGED' CHECK (status IN ('STAGED','ATTACHED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    attached_at TIMESTAMPTZ,
    CHECK ((status='STAGED' AND merchant_id IS NULL AND attached_at IS NULL)
        OR (status='ATTACHED' AND merchant_id IS NOT NULL AND attached_at IS NOT NULL))
);
CREATE UNIQUE INDEX uq_merchant_logo_attached ON merchant_logos(merchant_id) WHERE status='ATTACHED';
CREATE INDEX idx_merchant_logo_staged ON merchant_logos(owner_user_id, created_at) WHERE status='STAGED';

-- Registration request journal: same key + same body replays, a changed body conflicts.
CREATE TABLE merchant_registration_requests (
    owner_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_hash VARCHAR(64) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    merchant_id BIGINT NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (owner_user_id, key_hash)
);
