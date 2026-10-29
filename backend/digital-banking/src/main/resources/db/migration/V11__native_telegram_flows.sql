-- Keep native code delivery separate from browser popup receipts. Existing flows stay browser-only.
ALTER TABLE telegram_login_flows ADD COLUMN native_flow BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE telegram_login_flows ADD COLUMN redirect_uri VARCHAR(512);
ALTER TABLE telegram_login_flows ADD CONSTRAINT ck_native_telegram_redirect
    CHECK (NOT native_flow OR redirect_uri IS NOT NULL);
