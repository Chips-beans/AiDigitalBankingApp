-- Migration V16: User Wallets and Merchant Accounts Separation and Limits
-- 1. Add account_category column to accounts table (default 'WALLET')
ALTER TABLE accounts ADD COLUMN account_category VARCHAR(20) NOT NULL DEFAULT 'WALLET';
ALTER TABLE accounts ADD CONSTRAINT ck_account_category CHECK (account_category IN ('WALLET', 'MERCHANT'));

-- 2. Add merchant_id column referencing merchants table
ALTER TABLE accounts ADD COLUMN merchant_id BIGINT REFERENCES merchants(id) ON DELETE SET NULL;

-- 3. Indexes for efficient lookup and category separation
CREATE INDEX idx_accounts_user_category ON accounts(user_id, account_category);
CREATE INDEX idx_accounts_merchant_id ON accounts(merchant_id) WHERE merchant_id IS NOT NULL;
