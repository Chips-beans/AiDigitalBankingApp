-- =============================================================================
-- DATABASE MIGRATION SCRIPT: MERCHANT, FRAUD, AI, AND AUDIT MODULES
-- Database: PostgreSQL 14+
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. MERCHANT MODULE TABLES
-- -----------------------------------------------------------------------------

-- Merchant Status Enum
CREATE TYPE merchant_status AS ENUM (
    'PENDING',
    'ACTIVE',
    'SUSPENDED',
    'INACTIVE'
);

-- Merchants Table
CREATE TABLE merchants (
    id BIGSERIAL PRIMARY KEY,
    merchant_id VARCHAR(50) NOT NULL UNIQUE,
    store_name VARCHAR(150) NOT NULL,
    bakong_account_id VARCHAR(100) NOT NULL UNIQUE,
    merchant_city VARCHAR(100) NOT NULL,
    mcc VARCHAR(10) DEFAULT '5999',
    status merchant_status NOT NULL DEFAULT 'PENDING',
    owner_user_id BIGINT NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),

    -- Foreign Key linking to the 'users' table
    CONSTRAINT fk_merchants_owner_user FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE RESTRICT
);

-- Indexes for Merchant Lookups
CREATE INDEX idx_merchants_owner_user_id ON merchants(owner_user_id);
CREATE INDEX idx_merchants_status ON merchants(status);
CREATE INDEX idx_merchants_bakong_account ON merchants(bakong_account_id);


-- -----------------------------------------------------------------------------
-- 2. FRAUD MODULE TABLES
-- -----------------------------------------------------------------------------

-- Fraud Enums
CREATE TYPE risk_level AS ENUM (
    'LOW',
    'MEDIUM',
    'HIGH',
    'CRITICAL'
);

CREATE TYPE fraud_action AS ENUM (
    'ALLOW',
    'FLAG',
    'REQUIRE_2FA',
    'BLOCK'
);

-- Dynamic Fraud Rules Table
CREATE TABLE fraud_rules (
    id BIGSERIAL PRIMARY KEY,
    rule_code VARCHAR(50) NOT NULL UNIQUE,
    rule_name VARCHAR(150) NOT NULL,
    description TEXT,
    threshold_value NUMERIC(19, 2),
    velocity_limit INT,
    window_minutes INT,
    action_to_take fraud_action NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Flagged Transactions Log Table
CREATE TABLE flagged_transactions (
    id BIGSERIAL PRIMARY KEY,
    transaction_ref VARCHAR(100) NOT NULL,
    account_id VARCHAR(50) NOT NULL,
    amount NUMERIC(19, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL,
    triggered_rule_code VARCHAR(50),
    reason TEXT NOT NULL,
    risk_level risk_level NOT NULL,
    action_taken fraud_action NOT NULL,
    ip_address VARCHAR(45),
    device_id VARCHAR(100),
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes for Fraud Queries and Velocity Calculations
CREATE INDEX idx_flagged_tx_account_time ON flagged_transactions(account_id, created_at);
CREATE INDEX idx_flagged_tx_risk_level ON flagged_transactions(risk_level);
CREATE INDEX idx_flagged_tx_ref ON flagged_transactions(transaction_ref);


-- -----------------------------------------------------------------------------
-- 3. AI MODULE TABLES
-- -----------------------------------------------------------------------------

-- Insight Type Enum
CREATE TYPE insight_type AS ENUM (
    'SPENDING_ANALYSIS',
    'BUDGET_WARNING',
    'SAVING_TIP',
    'FINANCIAL_ADVICE'
);

-- User AI Insights Table
CREATE TABLE user_ai_insights (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    insight_type insight_type NOT NULL,
    generated_content TEXT NOT NULL,
    target_period VARCHAR(20), -- E.g., "2026-10"
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),

    -- Foreign Key linking to the 'users' table
    CONSTRAINT fk_ai_insights_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    -- Prevent duplicate insight cache for the same period and type per user
    CONSTRAINT uq_user_period_insight UNIQUE (user_id, target_period, insight_type)
);

-- Index for Fetching User Insights History
CREATE INDEX idx_ai_insights_user_created ON user_ai_insights(user_id, created_at DESC);


-- -----------------------------------------------------------------------------
-- 4. AUDIT MODULE TABLES
-- -----------------------------------------------------------------------------

-- Audit Severity Enum
CREATE TYPE audit_severity AS ENUM (
    'INFO',
    'WARN',
    'ERROR',
    'CRITICAL'
);

-- Compliance Audit Log Table
CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    module_name VARCHAR(50) NOT NULL,
    action VARCHAR(100) NOT NULL,
    performer_user_id VARCHAR(100),
    target_resource_id VARCHAR(100),
    severity audit_severity NOT NULL DEFAULT 'INFO',
    details TEXT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    success BOOLEAN NOT NULL DEFAULT TRUE,
    timestamp TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes for Security Audits & Compliance Reporting
CREATE INDEX idx_audit_logs_performer ON audit_logs(performer_user_id);
CREATE INDEX idx_audit_logs_module ON audit_logs(module_name);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_logs_severity ON audit_logs(severity);