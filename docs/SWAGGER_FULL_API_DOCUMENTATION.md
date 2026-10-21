# Complete Digital Banking API Documentation & Swagger UI Integration Guide

**Project:** Digital Banking & Smart Wallet  
**Document Version:** 1.0.0  
**Date:** 21 October 2026  
**Status:** Completed & Verified  

---

## 1. Overview & Context

Previously, the Swagger UI interface (`http://localhost:8080/swagger-ui/index.html`) displayed **only 4 categories of API endpoints** (`Authentication`, `Accounts`, `Transactions`, and `Staff demo tools`), totaling 14 endpoints.

### Why only 4 categories were displayed initially:
1. **Curated Foundation Milestone Group:** In `FoundationOpenApiConfig.java`, a single `GroupedOpenApi` bean named `foundation` was configured to include only the core banking paths matching `/api/v1/auth/**`, `/api/v1/accounts/**`, and `/api/v1/transactions/**`.
2. **SpringDoc Grouping Behavior:** When any `GroupedOpenApi` bean is registered, SpringDoc switches Swagger UI into grouped mode. Because only `foundation` was defined, Swagger UI's selector endpoint (`/v3/api-docs/swagger-config`) served only that group.
3. **Deferred Advanced Modules:** Other modules in the codebase (`payments`, `merchants`, `fraud`, `ai`, `audit`) had been scaffolded and implemented during earlier phases, but were intentionally excluded from the primary Foundation test contract until core banking was locked and verified.

### What has been implemented:
All API endpoints across all 8 modules have now been fully integrated, categorized with human-readable Swagger tags, documented with operation summaries, and configured into flexible Swagger UI definition groups.

---

## 2. Where Code and Comments Were Added

Clear comments (`// Added for Swagger UI ...` and `// Added: OpenAPI Operation description`) have been added to every modified file so you can easily track all additions.

### 2.1. OpenAPI Configuration
- **File:** [`backend/digital-banking/src/main/java/com/bank/digital_banking/config/OpenApiConfig.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/config/OpenApiConfig.java)
  - **Added `allApi()` bean:** Exposes **all** platform APIs under the `/api/v1/**` pattern. This provides a single view with all 9 categories.
  - **Added `paymentsGroupApi()` bean:** Groups Bakong KHQR payments and Merchant services (`/api/v1/payments/**`, `/api/v1/merchants/**`).
  - **Added `advancedServicesGroupApi()` bean:** Groups AI insights, fraud detection, and audit logging (`/api/v1/ai/**`, `/api/v1/fraud/**`, `/api/v1/audit/**`).
  - **Updated description:** Clearly explains how to toggle between the groups in Swagger UI.

- **File:** [`backend/digital-banking/src/main/java/com/bank/digital_banking/config/FoundationOpenApiConfig.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/config/FoundationOpenApiConfig.java)
  - **Updated `foundationApi()`:** Added `.displayName("Foundation (Core Banking)")` and comments so the core milestone remains cleanly accessible.

---

### 2.2. Controller Tags and Operation Summaries Added

Every non-foundation controller was updated with `@Tag(name = "...", description = "...")` and `@Operation(summary = "...", description = "...")` annotations:

| Controller File | Added Swagger Category Tag | Description Added | Endpoints Documented |
| :--- | :--- | :--- | :--- |
| [`BakongPaymentController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/payment/controller/BakongPaymentController.java) | **`Bakong Payments`** | Bakong KHQR payment generation, status verification, and webhook handling | 3 endpoints |
| [`MerchantController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/merchant/controller/MerchantController.java) | **`Merchants`** | Merchant onboarding, profile lifecycle, and KHQR merchant configuration | 8 endpoints |
| [`FraudRuleController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/fraud/controller/FraudRuleController.java) | **`Fraud Detection`** | Real-time transaction fraud evaluation, rule management, and flagged alerts | 4 endpoints |
| [`AIInsightController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/ai/controller/AIInsightController.java) | **`AI Insights`** | AI-powered financial insights, spending analysis, and chat assistant | 3 endpoints |
| [`AuditLogController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/audit/controller/AuditLogController.java) | **`Audit Logs`** | Immutable audit log query and administrative security investigation | 5 endpoints |

---

## 3. Complete Catalog of All Platform APIs (All 9 Categories)

When viewing the **`All APIs (Full Platform)`** definition in Swagger UI, you have access to **37 endpoints across 9 categories**:

```
├── 1. Authentication (6 endpoints)
├── 2. Accounts (3 endpoints)
├── 3. Transactions (3 endpoints)
├── 4. Staff demo tools (2 endpoints)
├── 5. Bakong Payments (3 endpoints)
├── 6. Merchants (8 endpoints)
├── 7. Fraud Detection (4 endpoints)
├── 8. AI Insights (3 endpoints)
└── 9. Audit Logs (5 endpoints)
```

---

### Category 1: `Authentication`
*Controller:* [`AuthController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/auth/controller/AuthController.java)  
*Base Path:* `/api/v1/auth`

| HTTP Method | Endpoint | Access Level | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/auth/request-otp` | Public | Request an email OTP for `SIGNUP` or `LOGIN` |
| `POST` | `/api/v1/auth/register` | Public | Register a new customer user and obtain initial JWT session tokens |
| `POST` | `/api/v1/auth/login` | Public | Sign in with password and email OTP; returns access & refresh tokens |
| `POST` | `/api/v1/auth/refresh` | Public | Rotate refresh token and get a fresh access token |
| `GET` | `/api/v1/auth/me` | Bearer Token | Retrieve authenticated user profile, roles, and current session ID |
| `POST` | `/api/v1/auth/logout` | Bearer Token | Revoke current user session on the server |

---

### Category 2: `Accounts`
*Controller:* [`AccountController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/account/controller/AccountController.java)  
*Base Path:* `/api/v1/accounts`

| HTTP Method | Endpoint | Access Level | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/accounts` | ROLE_CUSTOMER | Open a new zero-balance bank account (`SAVINGS`, `CHECKING`, etc.) |
| `GET` | `/api/v1/accounts/me` | ROLE_CUSTOMER | List all bank accounts owned by the authenticated customer |
| `GET` | `/api/v1/accounts/{accountNumber}` | ROLE_CUSTOMER | Get account balance and details for an owned account |

---

### Category 3: `Transactions`
*Controller:* [`TransactionController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/transaction/controller/TransactionController.java)  
*Base Path:* `/api/v1/transactions`

| HTTP Method | Endpoint | Access Level | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/transactions/transfer` | ROLE_CUSTOMER | Transfer funds between internal accounts (*Requires `Idempotency-Key` header*) |
| `GET` | `/api/v1/transactions/account/{accountNumber}` | ROLE_CUSTOMER | Paginated transaction history for an owned account |
| `GET` | `/api/v1/transactions/{referenceNumber}` | ROLE_CUSTOMER | Retrieve transaction details by transaction reference number |

---

### Category 4: `Staff demo tools`
*Controllers:* [`AccountController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/account/controller/AccountController.java) & [`TransactionController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/transaction/controller/TransactionController.java)

| HTTP Method | Endpoint | Access Level | Description |
| :--- | :--- | :--- | :--- |
| `PATCH` | `/api/v1/accounts/{accountNumber}/status` | ROLE_ADMIN, ROLE_BANK_EMPLOYEE | Update account status (`ACTIVE`, `FROZEN`, `CLOSED`) |
| `POST` | `/api/v1/transactions/deposit` | ROLE_ADMIN, ROLE_BANK_EMPLOYEE | Deposit demo test funds into an account (*Requires `Idempotency-Key` header*) |

---

### Category 5: `Bakong Payments`
*Controller:* [`BakongPaymentController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/payment/controller/BakongPaymentController.java)  
*Base Path:* `/api/v1/payments`

| HTTP Method | Endpoint | Access Level | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/payments/khqr/generate` | Bearer Token | Generate an EMVCo-compliant Bakong KHQR code payload (USD or KHR) |
| `GET` | `/api/v1/payments/verify/{md5Hash}` | Bearer Token | Check and verify settlement status for a Bakong transaction MD5 hash |
| `POST` | `/api/v1/payments/webhook` | External/Public | Webhook callback endpoint to receive asynchronous Bakong settlement events |

---

### Category 6: `Merchants`
*Controller:* [`MerchantController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/merchant/controller/MerchantController.java)  
*Base Path:* `/api/v1/merchants`

| HTTP Method | Endpoint | Access Level | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/merchants/register` | Bearer Token | Register a new merchant profile for business payments |
| `GET` | `/api/v1/merchants/{id}` | Bearer Token | Get merchant details by internal database ID |
| `GET` | `/api/v1/merchants/code/{merchantId}` | Bearer Token | Get merchant profile by external merchant code |
| `GET` | `/api/v1/merchants/owner/{ownerUserId}` | Bearer Token | List all merchants registered by a specific owner user |
| `GET` | `/api/v1/merchants/status/{status}` | Bearer Token | List merchants filtered by status (`PENDING`, `APPROVED`, etc.) |
| `PUT` | `/api/v1/merchants/{id}` | Bearer Token | Update merchant profile details (store name, MCC, city, etc.) |
| `PATCH` | `/api/v1/merchants/{id}/status` | Bearer Token | Update merchant status (approve, suspend, or reactivate) |
| `GET` | `/api/v1/merchants/{id}/khqr-config` | Bearer Token | Retrieve KHQR payment credentials and configuration for the merchant |

---

### Category 7: `Fraud Detection`
*Controller:* [`FraudRuleController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/fraud/controller/FraudRuleController.java)  
*Base Path:* `/api/v1/fraud`

| HTTP Method | Endpoint | Access Level | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/fraud/check` | Bearer Token | Evaluate an in-flight transaction against risk rules; returns risk score & action |
| `POST` | `/api/v1/fraud/rules` | ROLE_ADMIN, ROLE_BANK_EMPLOYEE | Define and persist a new fraud evaluation rule |
| `GET` | `/api/v1/fraud/flagged` | ROLE_ADMIN, ROLE_BANK_EMPLOYEE | Paginated list of transactions flagged by the risk engine |
| `GET` | `/api/v1/fraud/flagged/risk/{riskLevel}` | ROLE_ADMIN, ROLE_BANK_EMPLOYEE | List flagged transactions filtered by severity (`LOW`, `MEDIUM`, `HIGH`, `CRITICAL`) |

---

### Category 8: `AI Insights`
*Controller:* [`AIInsightController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/ai/controller/AIInsightController.java)  
*Base Path:* `/api/v1/ai`

| HTTP Method | Endpoint | Access Level | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/ai/insights/spending` | Bearer Token | Generate an AI spending breakdown, advice, and financial health score |
| `POST` | `/api/v1/ai/chat` | Bearer Token | Interactive AI financial assistant for user questions regarding budgeting/spending |
| `GET` | `/api/v1/ai/insights/user/{userId}` | Bearer Token | Historical spending insight reports for the authenticated customer |

---

### Category 9: `Audit Logs`
*Controller:* [`AuditLogController.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/module/audit/controller/AuditLogController.java)  
*Base Path:* `/api/v1/audit`

| HTTP Method | Endpoint | Access Level | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/audit/log` | Bearer Token | Record an asynchronous audit log entry for administrative/operational tracking |
| `GET` | `/api/v1/audit/user/{userId}` | ROLE_ADMIN, ROLE_BANK_EMPLOYEE | Retrieve audit trails of actions performed by or targeting a user |
| `GET` | `/api/v1/audit/module/{moduleName}` | ROLE_ADMIN, ROLE_BANK_EMPLOYEE | Filter audit logs by module name (e.g. `AUTH`, `ACCOUNT`, `TRANSACTION`) |
| `GET` | `/api/v1/audit/severity/{severity}` | ROLE_ADMIN, ROLE_BANK_EMPLOYEE | Filter audit logs by severity (`INFO`, `WARN`, `ERROR`, `CRITICAL`) |
| `GET` | `/api/v1/audit/range` | ROLE_ADMIN, ROLE_BANK_EMPLOYEE | Query audit logs within an ISO datetime range (`start` to `end`) |

---

## 4. How to Navigate Between Groups in Swagger UI

Open your browser to:
[http://localhost:8080/swagger-ui/index.html](http://localhost:8080/swagger-ui/index.html)

At the top right corner of Swagger UI, you will find the **Select a definition** dropdown menu. You can switch between 4 views at any time:

1. **`All APIs (Full Platform)` (`all`):**
   - Displays all 37 endpoints across all 9 categories.
   - Recommended for full platform exploration, frontend development, and integration.

2. **`Foundation (Core Banking)` (`foundation`):**
   - Displays the 14 core baseline endpoints (`Authentication`, `Accounts`, `Transactions`, `Staff demo tools`).
   - Clean view for Foundation QA and regression verification.

3. **`Payments & Merchants` (`payments`):**
   - Focuses strictly on Bakong KHQR payment generation, status verification, and merchant store management.

4. **`AI, Fraud & Audit` (`advanced-services`):**
   - Focuses on the AI Assistant, risk scoring rules, flagged transactions, and system audit logs.

---

## 5. Verification & Testing Evidence

All automated unit and integration tests continue to pass with 0 errors:
- **`FoundationReadinessTests`:** 4 tests passed, 0 failures (verifying that the `foundation` group retains its strict 14-path contract).
- **`PhaseZeroIntegrationTests`:** 34 tests passed, 0 failures (verifying JWT session lifecycle, password/OTP validation, and security schemes).
- **Compilation Check:** Full Maven build and test compilation succeeded without errors.
