# Swagger UI API Categories Analysis & Investigation

**Date:** 21 October 2026  
**Project:** Digital Banking & Smart Wallet  
**Investigated Component:** Backend OpenAPI / Swagger UI Configuration  

---

## 1. Executive Summary

When launching the Digital Banking backend and opening the Swagger UI interface (`http://localhost:8080/swagger-ui/index.html`), the interface displays **only 4 categories (tags) of API endpoints**:

1. **`Authentication`** (6 endpoints)
2. **`Accounts`** (3 endpoints)
3. **`Transactions`** (3 endpoints)
4. **`Staff demo tools`** (2 endpoints)

Although the codebase contains **8 controller classes** and **30+ endpoints** across multiple modules (such as AI insights, Bakong QR payments, fraud detection, merchant management, and audit logging), only the 4 categories above appear in Swagger UI.

### Why this happens:
1. **Active OpenAPI Grouping (`GroupedOpenApi`):** In [`FoundationOpenApiConfig.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/config/FoundationOpenApiConfig.java), the backend defines a single `GroupedOpenApi` bean named `foundation`. When at least one group bean exists, SpringDoc switches to grouped mode and only exposes the configured groups to Swagger UI's configuration (`/v3/api-docs/swagger-config`).
2. **Explicit Path Filtering:** The `foundation` group filters paths with `.pathsToMatch("/api/v1/auth/**", "/api/v1/accounts", "/api/v1/accounts/**", "/api/v1/transactions/**")`, which matches only 14 endpoints from `AuthController`, `AccountController`, and `TransactionController`.
3. **Operation Tag Overrides:** A global customizer (`foundationContracts`) assigns each of the 14 operations to one of four specific tags: `"Authentication"`, `"Accounts"`, `"Transactions"`, or `"Staff demo tools"`. Swagger UI uses OpenAPI tags as category groupings.
4. **Architectural Milestone Scope:** This was an intentional architectural decision for **Milestone F1 (Foundation)**. As documented in [`docs/BACKEND_COMPLETION_PLAN.md`](BACKEND_COMPLETION_PLAN.md), the project explicitly scoped the foundation baseline to core banking flows (OTP registration, account opening, internal transfers, and demo funding). Advanced features (Bakong QR, AI insights, fraud detection, merchant operations) were formally deferred and kept out of the foundation Swagger UI so client developers and QA test against verified contracts.

---

## 2. Investigation Steps & Findings

### Step 1: Scanning All Controllers in the Codebase
Scanning `backend/digital-banking/src/main` for Spring REST controllers revealed **8 controller files**:

| Controller Class | Base Request Mapping | Module | Status in Swagger UI |
| :--- | :--- | :--- | :--- |
| `AuthController.java` | `/api/v1/auth` | Authentication & Sessions | **Visible** (`Authentication`) |
| `AccountController.java` | `/api/v1/accounts` | Accounts & Balances | **Visible** (`Accounts`, `Staff demo tools`) |
| `TransactionController.java` | `/api/v1/transactions` | Transfers & Deposits | **Visible** (`Transactions`, `Staff demo tools`) |
| `AIInsightController.java` | `/api/v1/ai` | AI & Financial Insights | **Excluded** |
| `AuditLogController.java` | `/api/v1/audit` | System Audit Trails | **Excluded** |
| `BakongPaymentController.java` | `/api/v1/payments` | Bakong KHQR Payments | **Excluded** |
| `FraudRuleController.java` | `/api/v1/fraud` | Fraud Detection & Rules | **Excluded** |
| `MerchantController.java` | `/api/v1/merchants` | Merchant Onboarding & KHQR | **Excluded** |

---

### Step 2: Inspecting Swagger and OpenAPI Configurations
Searching for OpenAPI/Swagger configuration identified two key classes:

1. **[`OpenApiConfig.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/config/OpenApiConfig.java)**
   - Configures base OpenAPI info, Bearer JWT security scheme (`bearerAuth`), and documents:
     > *"Select the foundation group for delivered authentication, accounts, internal transfers, history and staff demo tools... Advanced payment, fraud and AI modules are outside the foundation milestone."*

2. **[`FoundationOpenApiConfig.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/config/FoundationOpenApiConfig.java)**
   - Defines the `foundationApi` `GroupedOpenApi` bean:
     ```java
     @Bean
     GroupedOpenApi foundationApi() {
         return GroupedOpenApi.builder().group("foundation")
                 .pathsToMatch("/api/v1/auth/**", "/api/v1/accounts", "/api/v1/accounts/**",
                         "/api/v1/transactions/**").build();
     }
     ```
   - Defines `GlobalOpenApiCustomizer foundationContracts()`:
     - Sets custom error schemas, request/response examples, nullability handling, and idempotency headers.
     - Calls the helper method `describe(...)`, which sets:
       ```java
       operation.setTags(List.of(tag));
       ```

---

### Step 3: Mapping the 14 Included Endpoints to the 4 Categories

The 14 endpoints included in the `foundation` group and their assigned categories are:

#### 1. Category: `Authentication` (6 endpoints)
- `POST /api/v1/auth/request-otp` — Request an email OTP (Public)
- `POST /api/v1/auth/register` — Register a customer and sign in (Public)
- `POST /api/v1/auth/login` — Sign in with password and email OTP (Public)
- `POST /api/v1/auth/refresh` — Rotate the JWT token pair (Public)
- `GET  /api/v1/auth/me` — Read current user identity and session (Authenticated)
- `POST /api/v1/auth/logout` — Revoke the current session (Authenticated)

#### 2. Category: `Accounts` (3 endpoints)
- `POST /api/v1/accounts` — Open a zero-balance account (ROLE_CUSTOMER)
- `GET  /api/v1/accounts/me` — List customer's own accounts (ROLE_CUSTOMER)
- `GET  /api/v1/accounts/{accountNumber}` — Read own account detail (ROLE_CUSTOMER)

#### 3. Category: `Transactions` (3 endpoints)
- `POST /api/v1/transactions/transfer` — Transfer between internal accounts (ROLE_CUSTOMER, Idempotency-Key required)
- `GET  /api/v1/transactions/account/{accountNumber}` — Read account transaction history (ROLE_CUSTOMER)
- `GET  /api/v1/transactions/{referenceNumber}` — Read transaction by reference (ROLE_CUSTOMER)

#### 4. Category: `Staff demo tools` (2 endpoints)
- `PATCH /api/v1/accounts/{accountNumber}/status` — Change account status (ROLE_ADMIN, ROLE_BANK_EMPLOYEE)
- `POST  /api/v1/transactions/deposit` — Add staff-controlled demo funds (ROLE_ADMIN, ROLE_BANK_EMPLOYEE, Idempotency-Key required)

---

### Step 4: Verification Against the Live Running Server

Querying the running backend confirmed the exact behavior:

1. **Swagger UI Configuration Endpoint (`/v3/api-docs/swagger-config`):**
   ```bash
   curl -s http://localhost:8080/v3/api-docs/swagger-config
   ```
   **Output:**
   ```json
   {
     "configUrl": "/v3/api-docs/swagger-config",
     "oauth2RedirectUrl": "http://localhost:8080/swagger-ui/oauth2-redirect.html",
     "urls": [
       {
         "url": "/v3/api-docs/foundation",
         "name": "foundation"
       }
     ],
     "validatorUrl": ""
   }
   ```
   *Swagger UI only receives `foundation` in its dropdown selector.*

2. **Tags present in `/v3/api-docs/foundation`:**
   ```bash
   curl -s http://localhost:8080/v3/api-docs/foundation | jq '[.paths[][].tags[]] | unique'
   ```
   **Output:**
   ```json
   [
     "Accounts",
     "Authentication",
     "Staff demo tools",
     "Transactions"
   ]
   ```
   *Exactly the 4 categories displayed in Swagger UI.*

3. **Tags present in raw `/v3/api-docs` (Full Spec):**
   ```bash
   curl -s http://localhost:8080/v3/api-docs | jq '[.paths[][].tags[]] | unique'
   ```
   **Output:**
   ```json
   [
     "Accounts",
     "Authentication",
     "Staff demo tools",
     "Transactions",
     "ai-insight-controller",
     "audit-log-controller",
     "bakong-payment-controller",
     "fraud-rule-controller",
     "merchant-controller"
   ]
   ```
   *The raw specification contains all controllers, but Swagger UI is configured to load only the `foundation` group.*

4. **Integration Test Verification:**
   In [`FoundationReadinessTests.java`](../backend/digital-banking/src/test/java/com/bank/digital_banking/FoundationReadinessTests.java), unit/integration tests explicitly verify:
   ```java
   if (document.endsWith("foundation")) {
       assertThat(api.path("paths").size()).isEqualTo(14);
       assertThat(api.path("paths").has("/api/v1/payments/khqr/generate")).isFalse();
       assertThat(api.path("paths").has("/api/v1/ai/chat")).isFalse();
       assertThat(api.path("paths").has("/api/v1/fraud/check")).isFalse();
   }
   ```

---

## 3. Why Was It Designed This Way?

According to project documentation ([`docs/BACKEND_COMPLETION_PLAN.md`](BACKEND_COMPLETION_PLAN.md) and [`docs/FOUNDATION_F1_IMPLEMENTATION.md`](FOUNDATION_F1_IMPLEMENTATION.md)):

1. **Phased Milestone Delivery:**
   The project was restructured on 17 October 2026 into a clear Foundation milestone (`F1` to `F5`). The primary objective was:
   > *"Register with email OTP -> sign in -> open an account -> receive staff demo funding -> view balance -> transfer to another internal account -> inspect history -> sign out."*

2. **Preventing Misleading API Documentation:**
   Modules like Bakong payments, merchant management, fraud rules, and AI chat were scaffolded but not yet fully wired to live external providers or completed frontend screens. Exposing them in the primary Swagger UI would lead frontend developers and QA engineers to attempt integrating endpoints whose business logic, rate limiting, and auditing had not yet passed the completion gate.

3. **Demarcation Between Customer and Staff Tools:**
   The endpoints `PATCH /accounts/{accountNumber}/status` and `POST /transactions/deposit` require staff roles (`ADMIN` or `BANK_EMPLOYEE`). Rather than grouping them under generic `Accounts` and `Transactions` tags, the team created the **`Staff demo tools`** category to clearly signal they are for administrative testing and demo seeding.

---

## 4. How to Show More Categories in Swagger UI (If Needed)

If the team wants all endpoints or additional modules visible in Swagger UI, there are two recommended approaches:

### Approach A: Add an "All" or "Advanced" Group to Swagger UI (Recommended)
This approach retains the `foundation` group (preventing breaks in `FoundationReadinessTests`) while adding a dropdown option in Swagger UI to view all endpoints.

In [`backend/digital-banking/src/main/java/com/bank/digital_banking/config/OpenApiConfig.java`](../backend/digital-banking/src/main/java/com/bank/digital_banking/config/OpenApiConfig.java), add a `GroupedOpenApi` bean:

```java
import org.springdoc.core.models.GroupedOpenApi;

@Bean
public GroupedOpenApi allApi() {
    return GroupedOpenApi.builder()
            .group("all")
            .pathsToMatch("/api/v1/**")
            .build();
}
```

Swagger UI will display a **Select a definition** dropdown at the top right, allowing users to toggle between:
- **`foundation`** (the 4 core categories: Authentication, Accounts, Transactions, Staff demo tools)
- **`all`** (all 8 controllers and all categories)

### Approach B: Add Fine-Grained Module Groups
If you prefer dedicated dropdown selections for each module:

```java
@Bean
public GroupedOpenApi paymentApi() {
    return GroupedOpenApi.builder()
            .group("payments-and-merchants")
            .pathsToMatch("/api/v1/payments/**", "/api/v1/merchants/**")
            .build();
}

@Bean
public GroupedOpenApi advancedToolsApi() {
    return GroupedOpenApi.builder()
            .group("ai-and-fraud")
            .pathsToMatch("/api/v1/ai/**", "/api/v1/fraud/**", "/api/v1/audit/**")
            .build();
}
```

---

## 5. Summary Table

| Category in Swagger UI | Controller | Endpoints Count | Key Endpoints | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **`Authentication`** | `AuthController` | 6 | `/auth/request-otp`, `/auth/register`, `/auth/login`, `/auth/refresh`, `/auth/me`, `/auth/logout` | Customer & staff onboarding, OTP verification, JWT session lifecycle |
| **`Accounts`** | `AccountController` | 3 | `/accounts`, `/accounts/me`, `/accounts/{accountNumber}` | Customer account creation and balance queries |
| **`Transactions`** | `TransactionController` | 3 | `/transactions/transfer`, `/transactions/account/{accountNumber}`, `/transactions/{referenceNumber}` | Customer internal transfers and paginated history |
| **`Staff demo tools`** | `AccountController`, `TransactionController` | 2 | `/accounts/{accountNumber}/status`, `/transactions/deposit` | Admin/Employee demo account freezing and simulated balance deposits |
