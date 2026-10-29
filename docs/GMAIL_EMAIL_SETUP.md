# Gmail email setup

Live development and email QA use Gmail SMTP with real recipient inboxes as of
19 October 2026. Historical F1/F2 Mailpit results remain historical evidence.

## Configure the sender

Edit existing assignments in `backend/digital-banking/.env`; preserve database,
JWT, and other settings. Keep exactly one assignment per key:

```dotenv
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=your_sender@gmail.com
MAIL_PASSWORD=your_gmail_app_password
MAIL_SMTP_AUTH=true
MAIL_STARTTLS=true
```

`MAIL_USERNAME` is the sending mailbox. Registration/login supplies the recipient
email independently. Keep real sender credentials in the ignored `.env`.

For this password-based SMTP integration, use the sender's Google app password.
Google requires 2-Step Verification to create app passwords; account policies can
restrict their availability. See Google's
[app-password instructions](https://support.google.com/accounts/answer/185833).

The `local` Spring profile inherits Gmail host/port/authentication/STARTTLS
defaults from `application.properties`. Existing `.env` values take precedence,
so remove old capture settings by replacing their assignments. The profile still
controls opt-in development banking fixtures independently of mail delivery.

Restart the backend after changing `.env`. Run from `backend/digital-banking`:

```powershell
.\mvnw.cmd spring-boot:run
```

## Verify live delivery

1. Use a real recipient inbox that you control.
2. For an unregistered address, request `SIGNUP` through
   `POST /api/v1/auth/request-otp`; for an existing enabled customer, request
   `LOGIN`. Eligibility is checked by the backend.
3. Confirm HTTP 200 and then confirm receipt in the actual Gmail Inbox or Spam
   folder. The public API intentionally returns a generic response for ineligible
   addresses, so HTTP 200 alone does not establish delivery.
4. The message subject is `Digital Wallet verification SIGNUP` or
   `Digital Wallet verification LOGIN`. Codes expire after five minutes under the
   current configuration. Respect the resend countdown and use the latest code.
5. Complete registration/login in the app when testing authentication. An OTP
   request and inbox confirmation alone do not create a customer or establish a
   complete authentication-flow test.

The automated Maven suite uses its isolated SMTP fixture for deterministic
regressions; it does not send messages to real inboxes. Actual Gmail delivery is
a separate live check. Mailpit is not started for that check.

## Verified delivery — 19 October 2026

- Gmail accepted a STARTTLS SMTP connection and the configured sender credentials.
- The backend requested a `SIGNUP` email from the configured Gmail sender to the
  user's confirmed recipient inbox at **15:09:42 UTC+07:00**. Exact addresses
  are retained only in the ignored local QA metadata.
- The API returned **HTTP 200** in 5.23 seconds with a 300-second code lifetime.
- The recipient confirmed **Received in Inbox** in this chat.
- Correlation ID: `9fb44a57-0299-41da-9c24-845f74d224f9`.
- Neither address was registered in the local customer database at the initial
  read-only check. No account was created or password assigned by this delivery test.

This verifies actual inbox delivery. It does not claim Gmail-based completion of
registration/login; earlier foundation authentication evidence is documented in
the respective QA reports.

After changing the example configuration and local-profile defaults, Maven
`verify` passed all **78 tests**, with **0 failures, 0 errors, and 0 skips**,
and rebuilt the packaged jar. This regression run used the isolated SMTP fixture.
The task-started Gmail QA backend was stopped after the delivery check; Gmail
settings remain in `.env` for the next normal startup.

Nonsensitive request metadata is retained locally at
`D:\CodexQa\AiDigitalBankingBackend\2026-10-19\gmail\delivery-result.json`.
The post-change regression log is `maven-verify.log` in the same directory.
Credentials and verification codes are excluded from this document and QA output.
## F3 authentication and account acceptance — 19 October 2026

After the earlier delivery-only check, F3 completed real Gmail-based registration
for two user-approved customer aliases, staff login for a separate local QA
fixture, and a later customer login through the Android app. The user supplied
the four actual inbox codes. Account opening, staff funding, balances/activity,
ownership, statuses, native restoration/rotation, uncertain-creation persistence,
and logout passed. See [F3 delivery and QA](FOUNDATION_F3_IMPLEMENTATION.md).
The earlier statement that no account was created applies to the delivery-only
check; F3 deliberately retained its new local QA identities and accounts.
