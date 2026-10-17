-- PostgreSQL NUMERIC permits NaN, which passes ordinary positivity constraints.
-- Preserve V8 and refuse an upgrade until any such legacy money is reconciled.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM accounts WHERE NOT (balance <= 9999999999999.99))
       OR EXISTS (SELECT 1 FROM transactions
                  WHERE NOT (amount <= 9999999999999.99 AND fee <= 9999999999999.99)) THEN
        RAISE EXCEPTION 'Financial preflight failed: non-finite money in accounts or transactions; reconcile before V9';
    END IF;
END $$;

ALTER TABLE accounts ADD CONSTRAINT ck_accounts_finite_money
    CHECK (balance <= 9999999999999.99);
ALTER TABLE transactions ADD CONSTRAINT ck_transactions_finite_money
    CHECK (amount <= 9999999999999.99 AND fee <= 9999999999999.99);
