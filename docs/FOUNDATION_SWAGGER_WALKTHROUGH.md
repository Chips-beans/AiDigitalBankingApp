# Foundation Swagger walkthrough (F1)

First follow [local setup](FOUNDATION_LOCAL_SETUP.md). Open
[Swagger](http://localhost:8080/swagger-ui/index.html), select **foundation**, and
open [Mailpit](http://127.0.0.1:8025) alongside it. All API paths below begin with
`/api/v1`. For each call, click **Try it out**, enter JSON/parameters, and **Execute**.

Public auth calls have no lock. Protected calls require a valid access token.
Registration and account opening return **201**; other successful calls return
**200**. The examples in Swagger match these contracts.

## 1. Register a sender

Choose a unique suffix for this run, such as `1017a`. This guide uses
`foundation.sender.1017a@example.test`. Use the exact same address through signup.
These are local capture addresses; no real email account is required.

POST `/auth/request-otp`:

```json
{
  "email": "foundation.sender.1017a@example.test",
  "purpose": "SIGNUP"
}
```

Expected **200** with this data (inside the success envelope):

```json
{
  "message": "If the address is eligible, a verification code has been sent",
  "expiresInSeconds": 300,
  "resendAfterSeconds": 60
}
```

Read the matching SIGNUP message in Mailpit. Use its actual six-digit code,
including leading zeroes. `123456` below is a placeholder.

POST `/auth/register`:

```json
{
  "username": "foundation.sender.1017a",
  "email": "foundation.sender.1017a@example.test",
  "password": "ChooseYourTestPassword!",
  "otpCode": "123456",
  "firstName": "Foundation",
  "lastName": "Sender",
  "deviceFingerprint": "swagger-sender-1017a",
  "deviceName": "Swagger on Windows",
  "deviceType": "WEB"
}
```

Required: username, email, password, otpCode, deviceFingerprint, deviceName.
Optional: firstName, lastName, deviceType. Username allows letters/digits/underscore/
dot/hyphen, 3–50 characters. Password is 8–72 characters and at most 72 UTF-8 bytes.
Keep the fingerprint stable for the same installation; no hardware ID is needed.

Expected **201**. Save `data.accessToken` and `data.refreshToken` privately.
Registration signs in immediately; no account is automatically opened.

## 2. Authorize and open the sender's account

Click **Authorize**, paste the sender's **access token only** under bearerAuth,
click Authorize, then Close. Do not include quotes or the `Bearer ` prefix.
Swagger adds the Authorization header. Swagger's Logout button only clears its
saved header; the backend `/auth/logout` endpoint revokes a server session.

- GET `/auth/me`: **200**, identity includes userId, username, email, roles,
  sessionId. Registration creates ROLE_CUSTOMER only.
- GET `/accounts/me`: **200**, `data: []` for the new customer.

POST `/accounts`:

```json
{
  "accountType": "SAVINGS",
  "currency": "USD",
  "initialDeposit": 0
}
```

Expected **201**, balance zero. Save `data.accountNumber` as **SENDER_ACCOUNT**.
GET `/accounts/{accountNumber}` with that number must return **200**.
Do not retry account opening blindly after a timeout; check your account list
first. Only transfers/deposits have the financial idempotency contract.

## 3. Register a receiver and open an account

Repeat steps 1–2 using a unique receiver identity, for example
`foundation.receiver.1017a` / `foundation.receiver.1017a@example.test` and
`swagger-receiver-1017a`. Request a separate SIGNUP code. Authorize the receiver
access token before opening their zero-balance USD account.

Save the receiver tokens and number as **RECEIVER_ACCOUNT**. Keep the two
identities/tokens separate. Both accounts must be active and use USD for this run.

## 4. Sign in as staff and add demo funding

POST `/auth/request-otp`:

```json
{
  "email": "employee.demo@example.test",
  "purpose": "LOGIN"
}
```

Read the employee's LOGIN code in Mailpit, then POST `/auth/login`:

```json
{
  "usernameOrEmail": "employee.demo@example.test",
  "password": "YOUR_DEV_SEED_PASSWORD",
  "otpCode": "123456",
  "deviceFingerprint": "swagger-employee-1017a",
  "deviceName": "Swagger on Windows",
  "deviceType": "WEB"
}
```

Replace password/code with actual values. All login fields except deviceType are
required. Username or email is accepted, but OTP requests always need the email.
Every login requires a fresh LOGIN OTP; a SIGNUP code cannot replace it.
Expected **200**, with ROLE_BANK_EMPLOYEE. Authorize this staff access token.

POST `/transactions/deposit`, setting the separate **Idempotency-Key** header
parameter to `f1-deposit-1017a`, and replacing the account number below:

```json
{
  "accountNumber": "SENDER_ACCOUNT",
  "amount": 100.00,
  "currency": "USD",
  "remark": "Local foundation demo funding"
}
```

Expected **200**, transaction type DEPOSIT, fee 0, status SUCCESS, and a reference.
This is staff-controlled local demo funding, not a live external payment.

Authorize the sender token again. GET the sender account: balance **USD 100.00**.
Attempt the same deposit endpoint as the sender: **403 ACCESS_DENIED**, no change.
The sender also receives **403** for PATCH `/accounts/{accountNumber}/status`.
Staff can set FROZEN/ACTIVE/CLOSED through that endpoint; restore ACTIVE before
the successful transfer below.

## 5. Verify ownership and transfer

While authorized as sender:

- GET the receiver's account detail: **404 RESOURCE_NOT_FOUND**.
- GET the receiver's account history: **404 RESOURCE_NOT_FOUND**.
- This privacy restriction does not prevent a permitted transfer to a known
  destination number. No public recipient-name lookup is provided.

POST `/transactions/transfer`, with header **Idempotency-Key: f1-transfer-1017a**:

```json
{
  "sourceAccountNumber": "SENDER_ACCOUNT",
  "destinationAccountNumber": "RECEIVER_ACCOUNT",
  "amount": 25.00,
  "currency": "USD",
  "remark": "Foundation transfer"
}
```

Replace both placeholders with the actual numeric account numbers. Expected
**200**; save `data.referenceNumber`. Sender balance becomes **75.00** and receiver
balance becomes **25.00**. Both remain USD. These exact balances assume fresh
zero-balance accounts and exactly the funding/transfer above.

Repeat the identical request using the same key: **200** with the original
reference and no further debit. Change amount to 30 but keep that key:
**409 IDEMPOTENCY_CONFLICT**, balances unchanged. Restore the original payload
when retrying the original operation. New transfer intentions need new keys.

If the response is lost, retry its identical payload with its original key;
do not generate another key merely because you did not receive a response.

USD supports at most two decimal places; KHR whole units only. Accounts must
have the same currency. Transfers must be positive, use different accounts,
and not exceed available funds. The current transfer fee is zero.

## 6. Inspect history and transaction details

As sender, GET `/transactions/account/{accountNumber}?page=0&size=10` using the
sender number. Expect **200**, with a deposit and transfer. GET
`/transactions/{referenceNumber}` using the saved transfer reference: **200**.

Switch authorization to receiver. Their balance is **25.00** and history shows
the incoming transfer; they can also read that transfer's reference. Incoming or
outgoing display is relative to the account being viewed, not a separate posting.

All success responses use this envelope (logout omits data):

```json
{
  "success": true,
  "message": "...",
  "data": {},
  "timestamp": "2026-10-17T00:00:00Z"
}
```

The type of data depends on the API:

| API | data fields / structure |
| --- | --- |
| OTP | message, expiresInSeconds, resendAfterSeconds; never the code |
| Register/login/refresh | userId, email, username, roles, sessionId, accessToken, refreshToken, tokenType, expiresInMs, refreshExpiresAt |
| Current identity | userId, username, email, roles, sessionId |
| Account creation/detail | id, accountNumber, accountType, currency, balance, status, createdAt |
| Account list | Array of account objects; page/size query bounds, no page metadata envelope |
| Transfer/deposit/detail | id, referenceNumber, sourceAccountNumber, destinationAccountNumber, amount, fee, currency, transactionType, status, remark, createdAt |
| Transaction history | content array of transactions, pageNo, pageSize, totalElements, totalPages, last |

A deposit has a null sourceAccountNumber. Page numbering starts at zero, size is
1–100. Dates/IDs in these examples are illustrative; use the actual response.

## 7. Refresh and log out

For the current customer, POST `/auth/refresh` (no bearer token required):

```json
{
  "refreshToken": "PASTE_CURRENT_REFRESH_TOKEN"
}
```

Expected **200** with a replacement pair. Save the **new refresh token** and update
Swagger authorization with the **new access token**. Default access lifetime is
15 minutes; consult expiresInMs for actual configuration. The session's default
absolute lifetime is seven days; refresh does not extend it.

Do not reuse the old refresh token during the normal flow: that returns
**401 REFRESH_REUSED** and revokes the entire session. A refresh token cannot be
used in Swagger's access-token authorization field.

With the new access token, POST `/auth/logout` with no body: **200**, message
Session revoked. GET `/auth/me` using that token: **401 SESSION_INVALID**.
The refresh token is also rejected after logout. Clear Swagger's authorization.
Log out other test sessions separately if you saved them.

## Failure checks and completion

| Check | Expected result |
| --- | --- |
| Protected call without token | 401 AUTHENTICATION_REQUIRED |
| Invalid required fields / OTP format | 400 VALIDATION_FAILED; inspect fieldErrors |
| Wrong password | 401 AUTHENTICATION_FAILED |
| Wrong/expired/used OTP | 401 OTP_INVALID / OTP_EXPIRED / OTP_USED |
| Duplicate username/email | 409 IDENTITY_UNAVAILABLE |
| Nonzero initialDeposit | 400 VERIFIED_FUNDING_REQUIRED |
| Customer invokes staff funding/status | 403 ACCESS_DENIED |
| Foreign account/history | 404 RESOURCE_NOT_FOUND |
| Insufficient funds | 400 INSUFFICIENT_FUNDS |
| Transfer involving a frozen account | 409 ACCOUNT_INACTIVE |
| Missing Idempotency-Key | 400 IDEMPOTENCY_KEY_REQUIRED |
| Used key with changed payload | 409 IDEMPOTENCY_CONFLICT |
| Too many OTP/login requests | 429 with Retry-After and retryAfterSeconds |
| Mailpit stopped / incorrect mail configuration | 503 OTP_DELIVERY_UNAVAILABLE for eligible OTP requests |

Errors use success=false, error, message, status, path, timestamp, fieldErrors,
retryAfterSeconds. The error field is a stable code; do not match message text.

F1 passes when local OTP delivery, documented core calls, correct Swagger
statuses/security, zero-balance account creation, staff funding, one-posting
transfer retries, history, refresh/logout, and role/ownership rejection all work.
AI, fraud scoring, QR payments, and the other deferred modules are not required.
