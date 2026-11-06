# Kesor Bank — deployment and operations

Updated 7 November 2026, Asia/Phnom_Penh. This is the single place for **how the project is hosted
and how to change it safely**: what is live, where every setting lives, and step-by-step runbooks for
the usual changes. Product behaviour stays in [CUSTOMER_APP.md](CUSTOMER_APP.md) and
[MERCHANT_APP.md](MERCHANT_APP.md); progress and agent rules stay in
[PROJECT_PROGRESS_AND_AGENT_GUIDE.md](PROJECT_PROGRESS_AND_AGENT_GUIDE.md). Record dated deployment
events in that guide's §8 log, and update this file when the setup itself changes.

> **Purpose and lifetime.** A short live run (about 5 days from 5 Nov 2026) of both Flutter apps
> against a hosted backend for a university banking case study. It is not a production bank: test
> money, debug-signed APKs, internal QR only.

---

## 1. What is live

| Item | Value |
| --- | --- |
| Backend URL | `https://backend-production-18646.up.railway.app` |
| API base used by both apps | `https://backend-production-18646.up.railway.app/api/v1` |
| Swagger UI (public) | `https://backend-production-18646.up.railway.app/swagger-ui/index.html` |
| Host | Railway, **Trial** plan ($5 credit / 30 days from 5 Nov 2026 — ends about **5 Dec 2026** or when the credit is used) |
| Railway workspace / project / environment | `re4chh's Projects` / `superb-respect` / `production` |
| Services | `backend` (this repo, Dockerfile), `Postgres` (Railway template `postgres-ssl:18`, volume `postgres-volume-Dubs`), and the isolated `Showcase Website` (Nginx static site) |
| Showcase website | `https://showcase-website-production.up.railway.app` — deployment `b64073e6-b37a-448f-8425-388ebc0c1d48` SUCCESS, 6 Nov 2026. APK hosting deferred by the user. |
| Region | US East (`iad`) for both services |
| Deployed code | `main` commit **`c3957fc7785dedd2ba6e77d4a0f5bd66a03611af`**, including backend review fixes `9217244`. Deployment **`f97bf1e0-6079-4c16-9bd8-6bd14328a80b` SUCCESS**, 7 Nov, isolated CLI upload. Snapshot: 278 files, SHA-256 `cbb66365562007cfc18cb41c36b219797ed8c2a585dac0151912de52e217490b`. Schema V21, configuration/database/domain preserved. Previous deployment `8fc7d198-bdc9-4a93-bd16-793b8c6b9668` retained as rollback reference. |
| Spring profile | `dev` (see §4 for why) |
| Database schema | Flyway **V21** (created from empty on first boot) |
| OTP email | Gmail API over HTTPS (`MAIL_PROVIDER=gmail-api`), sender = the user's own Gmail account |
| Telegram | Native Android flow enabled; browser/web flow not configured |
| AI assistant | **On** since 6 Nov 2026: the seven `AI_*` variables were copied from `.env` (Groq, `qwen/qwen3.8-27b`). Before that the app showed "The assistant is unavailable" because Railway had none. In-app check on a device still pending. |
| Pilot APKs | Latest wallet/auth refresh from `c6a9f8b`, debug/dev. customer_app: 245,526,174 bytes, SHA-256 `03bbfe42c152ea830e358cc3995c2a4937c00fad7f6b438673ed7308aed20ec7`; merchant_app: 231,059,332 bytes, SHA-256 `ee2a462b55135fd41e7ec2146e0d550670cc51082c4f8d92f0709f8f42a18a3e`. Canonical paths unchanged, versioned `.local/apk/20261106-161530/`; old APKs archived. |

Both APKs include the latest recorded Flutter designs, including both splashes and the Customer
Wallets, Wallet/Transaction Detail and three-question AI Assistant redesigns, plus linked merchant
wallet visibility and the Merchant sign-in diagnostics/recovery refresh. Current versioned copies
are in each app's `.local/apk/20261106-161530/`; older APKs remain in their versioned/archive folders.
Signatures match the previous APKs. Installation and device acceptance remain pending.

**7 Nov backend matches main:** the user-authorized deployment from `main` commit **`c3957fc`**
is **SUCCESS**, deployment **`f97bf1e0-6079-4c16-9bd8-6bd14328a80b`**. It includes the review
fixes committed in `9217244`. All environment/service configuration fingerprints, the 25
backend variables/references, existing domain, Postgres deployment/instance/database volume
and showcase service match the before-state. Schema remains **V21**; all 20 migrations were
validated and Flyway reported no migration necessary. Gmail API remains active.
Swagger/foundation OpenAPI return 200; protected accounts/Merchant/pair routes return 401
without authentication. No authenticated money operation or APK/device work was performed.
Evidence: `.local/railway-backend-main-20261107/`; product evidence: Customer §28.

**6 Nov source publication:** banking updates were committed/pushed as `33595d6`; the live
backend is already identical to that commit's backend source. Verified Swagger/foundation
OpenAPI 200, PIN Home preview present, personal accounts/Merchant session 401 without auth.
The current `20261106-161530` APK refresh above includes the subsequently implemented linked
merchant-wallet visibility and Merchant auth diagnostics/recovery fixes. Installation and device
acceptance remain separate work. See progress guide §8.

### Showcase website hosting

The user authorized deployment to their empty **Showcase Website** service
`57761625-19f6-4f2f-ba34-193668277189`, in production environment
`a7d550e4-e298-45d2-9c87-5bc778731653`, project
`c4ac8b7a-7a1a-4f08-9060-d0b444f05eda`. Its public domain targets Nginx port **80**.
`showcase/hosting/` contains the Dockerfile, allowlist and Nginx configuration. The final
website-only package is `.local/showcase-deploy-20261106/website-only-final` (80 files,
9,169,755 bytes), with a sibling manifest and upload log. It contains public assets only,
excluding APKs, credentials and banking source. GitHub pushes do not redeploy this service.

For another authorized deployment, prepare a fresh isolated package with these hosting files
and current built site assets, then pass **all three explicit project/environment/service IDs**
to `railway up <package> --path-as-root --no-gitignore --detach --json`. Do not deploy the repo
root or rely on the CLI's backend link. Verify the deployment status, public HTTPS and protected
banking service configurations afterward.

The user explicitly deferred APK hosting: deployed download routes are not ready. A separate
showcase-only volume (`32d81461-0013-47f1-a309-020c0519c763`) remains at `/apk-downloads`;
its incomplete staging files are not verified downloads. No banking service, deployment,
configuration or database volume was changed. The temporary task SSH key was revoked and its
local private/public files removed. Public UI checks at 1440/390/320px passed with EN/KM,
no horizontal overflow, broken loaded images or runtime errors; HTTP 200 confirmed.

### Showcase APK downloads (local preparation only)

The showcase's two APK buttons download the existing canonical Railway builds as `Kesor Bank.apk`
and `KesorMerchant.apk`. `npm --prefix showcase run dev` and `npm --prefix showcase run build`
first run `showcase/scripts/sync-apks.mjs`. This reads `.local/apk-refresh-active.json` and that
release's `verification.json`, checks the canonical files against their recorded size/SHA-256 and
Railway/signature checks, then copies the pair into ignored `showcase/public/downloads/`.
It does **not** build or install an APK or change Railway.

The production build includes `/downloads/kesor-bank.apk`, `/downloads/kesor-merchant.apk` and
an integrity `manifest.json` in `showcase/dist/downloads/`. Preparation fails if either canonical
file is missing, differs from the latest verified release, or lacks the expected verification.
After an authorized APK refresh, rerun the showcase build to pick up the latest verified pair.
`npm --prefix showcase run sync:apks` also prepares downloads for an already-running dev server.

APKs, generated download metadata, `dist/` and `dist-website/` stay out of Git. A new
checkout needs canonical APKs and verification records only for the guarded `dev`/`build`
commands. For website work without APKs, run `npm --prefix showcase ci`, then
`npm --prefix showcase run dev:website` or `npm --prefix showcase run build:website`.
The latter writes a separate `dist-website/`, filtering out `public/downloads/` even when
it already exists. Preview it with `npm --prefix showcase run preview:website`.
The default guarded commands and APK integrity checks are unchanged. Details:
[showcase README](../showcase/README.md). A website-only build does not verify its download links.
The website is now published, but its deployment deliberately excludes these
APK artifacts at the user's request. Local download verification does not establish hosted
download availability; APK hosting remains separate work.

### Expiry dates to watch

| What | When | Symptom | Fix |
| --- | --- | --- | --- |
| Gmail refresh token (Google consent screen in **Testing** mode) | About **7 days after creation** — created 5 Nov 2026, so about **12 Nov 2026** | OTP requests return `503 OTP_DELIVERY_UNAVAILABLE`; logs show `Gmail OAuth token refresh failed with HTTP 400 (invalid_grant)` | Runbook §6.6 |
| Railway Trial | About 5 Dec 2026 or $5 used | Services stop | Upgrade or tear down (§6.10) |

### Housekeeping still open
- A **detached, unused volume `postgres-volume`** remains in the project from the first (mistaken) Postgres service. The live database uses `postgres-volume-Dubs`. The user may delete `postgres-volume` in the dashboard; never delete `postgres-volume-Dubs`.

---

## 2. Architecture

```
 Android phone/tablet
 ┌───────────────────────┐   HTTPS (Railway edge, TLS)   ┌────────────────────────────┐
 │ Customer App (APK)    │ ────────────────────────────▶ │ backend  (Spring Boot 4,   │
 │ Merchant App (APK)    │   /api/v1/...                 │ Java 21, Docker, profile   │
 └───────────────────────┘                               │ dev, port $PORT)           │
        │  app-to-app approval (custom schemes,          └──────┬─────────┬───────────┘
        │  same device, no server involved)                     │ private │ outbound HTTPS (443)
        ▼                                                       ▼ network ▼
  Telegram app ──▶ app937652339-login.tg.dev/tglogin     Postgres 18     Gmail API (OTP email)
  (native login returns to the Customer App)             (volume)        oauth.telegram.org (Telegram OIDC)
                                                                         Groq (AI, on)
```

Key facts:
- **Railway blocks outbound SMTP** (ports 25/465/587) on Trial/Hobby plans, which is why OTP email uses the Gmail API over HTTPS instead of `smtp.gmail.com:587`. Render's free tier blocks SMTP too.
- The backend reaches Postgres over Railway's private network (`postgres.railway.internal:5432`).
- Profile photos and shop logos are stored in PostgreSQL (`BYTEA`), so the container's temporary disk is never relied on — no volume is attached to `backend`.
- Native Telegram login returns through Telegram's own App Link, independent of the backend host, so changing the backend URL does not need a BotFather change.

---

## 3. Rules for any session that touches the deployment

1. **Ask the user first** before anything that changes the live system: `railway up`, changing or deleting Railway variables, services, volumes or domains, building/installing APKs. Reading status and logs is fine.
2. **Secrets never appear in chat, docs, logs or commits.** Railway variable values are copied from the ignored `backend/digital-banking/.env` by a script that does not print them, and verified by comparison (`-ceq`) or length only. Never run `railway variables` without `--json` piped into a names-only filter — the plain command prints every value.
3. **Always target the `backend` service explicitly** (`--service backend`) or confirm `railway status` shows `backend` as the linked service. On 5 Nov 2026 a `railway up` while the CLI was linked to `Postgres` replaced the database container with the backend; it had to be deleted and recreated. The CLI in `backend/digital-banking` is currently linked to `backend`.
4. **Never delete** the `Postgres` service or `postgres-volume-Dubs` during the live run (all accounts and balances live there), and **never change `JWT_SECRET`** (in `dev` it also derives the PIN pepper and Merchant recovery key: changing it signs everyone out and breaks existing PINs and merchant sign-in).
5. Do not delete the `backend` service or its domain: a new URL means rebuilding and reinstalling both APKs.
6. Applied Flyway migrations are immutable (guide §3 rule 11). New schema changes are new versions; Railway applies them on the next boot.
7. `railway up` uploads the **working tree as it is**, including uncommitted changes. Deploy only from a clean, tested tree, and record the commit in the guide's §8 log.
8. Record every deployment event (what, commit, evidence, what is not verified) as a dated entry in the guide's §8.

---

## 4. Configuration

### Build (`backend/digital-banking/Dockerfile`)
- Build stage: `maven:3.9-eclipse-temurin-21`, `mvn -DskipTests package` (tests run on the workstation before deploying; the Maven image avoids the wrapper's curl/wget dependency).
- Runtime: `eclipse-temurin:21-jre-jammy`, non-root user, `TZ=Asia/Phnom_Penh`, `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=70 -XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError -Xss512k`, listens on Railway's `PORT` (fallback `SERVER_PORT`, then 8080).
- `backend/digital-banking/.dockerignore` keeps `.env`, `.local/`, `target/` and `scripts/` out of the build context. `railway up` also skips git-ignored files.

### Railway variables on `backend`

| Variable | Value / source | Notes |
| --- | --- | --- |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | `${{Postgres.PGHOST}}`, `${{Postgres.PGPORT}}`, `${{Postgres.PGDATABASE}}`, `${{Postgres.PGUSER}}`, `${{Postgres.PGPASSWORD}}` | Railway reference variables; resolve to the private host. |
| `DB_POOL_MAX_SIZE` / `DB_POOL_MIN_IDLE` | `5` / `1` | Small instance. |
| `SPRING_PROFILES_ACTIVE` | `dev` | `MerchantAuthConfig` accepts the debug custom-scheme approval links and `MerchantOnboardingPolicy` activates new shops only under `local`/`dev`/`test`. `local` would also create demo seed users. `staging`/`prod` would disable Merchant sign-in with these APKs. |
| `JWT_SECRET` | Generated once for Railway (32 random bytes, Base64); differs from the local one | Never rotate during the run (rule 4). |
| `MAIL_PROVIDER` | `gmail-api` | `smtp` is the code default (local development and tests). |
| `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN`, `GMAIL_SENDER` | Copied from local `.env` | Google Cloud OAuth client (Web application) + refresh token with scope `https://www.googleapis.com/auth/gmail.send`. |
| `TELEGRAM_CLIENT_ID`, `TELEGRAM_CLIENT_SECRET`, `TELEGRAM_NATIVE_REDIRECT_URI` | Copied from local `.env` | Native Android Telegram login. `TELEGRAM_REDIRECT_URI`/`TELEGRAM_FRONTEND_ORIGIN` deliberately not set (web flow). |
| `TEST_OPENING_FUNDING_ENABLED` | `true` | New USD/KHR wallets get 200.00 / 100,000 test credit (allowed only in non-production profiles). |

Not set on purpose: `PORT` (Railway injects it), `DEV_SEED_*`, `MAIL_*` SMTP settings, `MERCHANT_*` (development defaults apply under `dev`).

Optional, not set: `SERVER_FORWARD_HEADERS_STRATEGY=native` so per-IP rate limits see client IPs instead of Railway's proxy (only effective if Tomcat trusts the proxy address; unverified).

### Where the email code lives
- `module/auth/service/impl/MailProviderConfig.java` — chooses the `EmailService` from `app.mail.provider` (`MAIL_PROVIDER`); unknown value stops startup; logs which Gmail variable *names* are missing.
- `GmailApiEmailService.java` — refresh-token → access-token (cached until 60 s before expiry), base64url MIME to `gmail/v1/users/me/messages/send`, retry once after 401, 5 s timeouts, credentials only over HTTPS/loopback; every failure is `503 OTP_DELIVERY_UNAVAILABLE`; logs only HTTP status and OAuth error code.
- `EmailServiceImpl.java` — the SMTP sender (unchanged behaviour). `OtpEmailText.java` — shared subject/body.
- Tests: `src/test/.../module/auth/service/impl/GmailApiEmailServiceTests.java` (loopback fake of Google's endpoints; never calls Google).

---

## 5. Tools and access

| Tool | State on the workstation |
| --- | --- |
| Railway CLI | Installed globally with `npm install -g @railway/cli`; logged in as the user; `backend/digital-banking` linked to project `superb-respect`, environment `production`, service `backend`. |
| Railway dashboard | <https://railway.com/dashboard> → project `superb-respect`. |
| GitHub | Repo `Chips-beans/AiDigitalBankingApp` belongs to a friend's account; Railway is **not** connected to it, so pushes do not deploy. |
| Docker | Not installed; the image is only built by Railway. |
| adb | `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe` (not on PATH). |
| Google Cloud | Project with the Gmail API enabled and an OAuth client; consent screen in **Testing** with the sending account as test user. |

---

## 6. Runbooks

Run commands from `backend/digital-banking` unless stated otherwise. Every runbook ends with a dated
entry in the guide's §8.

### 6.1 Check health and logs (read-only, no approval needed)
```bash
railway status
railway deployment list --service backend
railway logs --service backend --deployment
```
Healthy startup log lines: `Successfully applied … now at version vNN` (or `Schema "public" is up to date`), `OTP email is delivered through the Gmail API`, `Started DigitalBankingApplication`.
Quick HTTPS probe: `GET /swagger-ui/index.html` → 200; `GET /api/v1/accounts` without a token → 401.

### 6.2 Deploy a backend code change
1. Make the change on a branch; keep money/auth rules from the guide §3 and §7.
2. Run the full suite on the workstation (about 5 minutes, one heavy job at a time):
   ```bash
   ./mvnw.cmd -o test
   ```
   Do not deploy on a red suite.
3. Commit (only if the user asked) so the deployed state is identifiable; note the commit.
4. With the user's approval, upload and build:
   ```bash
   railway up --service backend
   ```
   The build takes a few minutes; the switch-over causes roughly 30–60 s of downtime.
5. Verify with §6.1 (status `SUCCESS`, healthy log lines, probes). Then exercise the changed endpoint.
6. APKs do **not** need rebuilding for backend-only changes (the URL is unchanged).

### 6.3 Add a database migration
1. Add `src/main/resources/db/migration/V22__<name>.sql` (next free number); never edit an applied file.
2. Bump `FoundationHandoffTests` (`getVersion()` and applied-count assertion), run the full suite.
3. Deploy with §6.2. Flyway applies it at startup; confirm `now at version v22` in the logs.
4. There are no automatic backups on the Trial database. For a risky migration, ask the user whether to take a manual dump first (needs a Postgres client and the database's public URL, which is not enabled now).

### 6.4 Change or add a Railway variable
Any change triggers an automatic redeploy.
- **Plain values** (flags, sizes): dashboard → `backend` → **Variables**, or
  ```bash
  railway variables --service backend --set "DB_POOL_MAX_SIZE=5"
  ```
- **Secret values**: copy from the ignored `.env` without printing (PowerShell, from `backend/digital-banking`):
  ```powershell
  $envFile=@{}; Get-Content .env | % { if ($_ -match '^\s*([A-Z_]+)\s*=(.*)$') { $envFile[$matches[1]]=$matches[2].Trim() } }
  $keys='NAME_ONE','NAME_TWO'
  $a=@('variables','--service','backend'); foreach($k in $keys){ $a+='--set'; $a+="$k=$($envFile[$k])" }
  & railway @a *> $null; "exit=$LASTEXITCODE"
  $v = railway variables --service backend --json | ConvertFrom-Json
  foreach($k in $keys){ "{0} matches .env: {1}" -f $k, ($v.$k -ceq $envFile[$k]) }
  ```
- **List names only** (never values):
  ```powershell
  (railway variables --service backend --json | ConvertFrom-Json).PSObject.Properties.Name | ? { $_ -notmatch '^RAILWAY_' }
  ```
- Then wait for the redeploy and check §6.1. Update the variable table in §4 of this file.

### 6.5 Turn on the AI assistant
The assistant needs `AI_ENABLED=true`, `AI_CUSTOMER_CONTEXT_ENABLED=true`, `AI_API_KEY` (secret), and normally `AI_API_URL`, `AI_MODEL`, `AI_JSON_MODE`, `AI_REASONING_EFFORT` (values and meaning: guide §4 backend configuration table; provider is Groq). With the user's approval copy them from `.env` with §6.4, then check the assistant in the app. Groq free-tier limits are low; see CUSTOMER_APP.md for the assistant's behaviour.

### 6.6 Renew the Gmail refresh token (about every 7 days)
1. The user opens <https://developers.google.com/oauthplayground>, gear icon → tick **Use your own OAuth credentials** (Access type **Offline**) → same client ID/secret as in `.env`.
2. Step 1: scope `https://www.googleapis.com/auth/gmail.send` (typed by hand) → **Authorize APIs** → sign in with the sending account.
3. Step 2: **Exchange authorization code for tokens** → copy the refresh token into `GMAIL_REFRESH_TOKEN` in `.env` (never into chat).
4. Copy that one variable to Railway with §6.4, wait for the redeploy, request a code (§7) and check the inbox.

Errors: `unauthorized_client` = token issued for another client (the "own credentials" box was not ticked first); `redirect_uri_mismatch` = add `https://developers.google.com/oauthplayground` to the OAuth client; `access_denied` = account missing from Test users; `invalid_scope` = scope text corrupted.

### 6.7 Rebuild the APKs (Flutter change, or a new backend URL)
Only with the user's approval; one build at a time (8 GB RAM). From each app directory:
```powershell
$env:GRADLE_OPTS='-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1'
# frontend/customer_app
flutter build apk --debug --dart-define=APP_ENV=dev --dart-define=APP_MODE=api --dart-define=API_BASE_URL=https://backend-production-18646.up.railway.app/api/v1
# frontend/merchant_app
flutter build apk --debug --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=https://backend-production-18646.up.railway.app/api/v1
```
Copy `build/app/outputs/flutter-apk/app-debug.apk` to `.local/apk/Kesor Bank.apk` / `.local/apk/KesorMerchant.apk`, then verify (from the repo root):
```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$url='https://backend-production-18646.up.railway.app/api/v1'
foreach ($p in 'frontend\customer_app\.local\apk\Kesor Bank.apk','frontend\merchant_app\.local\apk\KesorMerchant.apk') {
  $zip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path $p))
  $envCount=@($zip.Entries | ? { $_.Name -match '^\.env' }).Count
  $k=$zip.Entries | ? { $_.FullName -like '*flutter_assets/kernel_blob.bin' }
  $ms=New-Object IO.MemoryStream; $s=$k.Open(); $s.CopyTo($ms); $s.Close(); $zip.Dispose()
  "{0}: .env={1} url={2} sha256={3}" -f (Split-Path $p -Leaf), $envCount, [Text.Encoding]::UTF8.GetString($ms.ToArray()).Contains($url), (Get-FileHash $p).Hash
}
```
Expect `.env=0 url=True`. Record sizes and SHA-256 in §1 and the guide's §8.

Rules: debug signing key from this workstation (native Telegram's App Link was proven with it; a different key may stop Telegram returning to the app). Release signing and HTTPS App Links are not set up. Install both apps on the **same device** (Merchant sign-in is approved in the Customer App).

### 6.8 Install on a device
With the user's approval and the device connected/unlocked:
```powershell
$adb="$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb devices -l
& $adb -s <device-id> install -r "frontend\customer_app\.local\apk\Kesor Bank.apk"
& $adb -s <device-id> install -r "frontend\merchant_app\.local\apk\KesorMerchant.apk"
```
`-r` keeps app data. Secure storage is scoped by API URL, so after switching from a local build users sign in again. Do not touch the tablet's accessibility/developer settings (guide §3 rule 12).

### 6.9 Roll back a bad backend deploy
1. Dashboard → `backend` → **Deployments** → an earlier `SUCCESS`/`REMOVED` deployment → **⋮ → Redeploy** (the user does this; the CLI has no safe rollback command). Or check out the last good commit and run §6.2.
2. A rollback does **not** undo database migrations. If a bad migration ran, fix forward with a new version.

### 6.10 End of the live run (tear-down)
With the user's approval: delete the Railway project (dashboard → project settings → Delete Project); revoke the Gmail token (Google Account → Security → Third-party access → remove the app) and delete the Google Cloud project; optionally uninstall the APKs. Record it in the guide's §8 and mark §1 of this file as retired.

---

## 7. Smoke tests against the live URL

| Check | Request | Expected |
| --- | --- | --- |
| Up | `GET /swagger-ui/index.html` | 200 |
| Auth enforced | `GET /api/v1/accounts` | 401 |
| OTP email | `POST /api/v1/auth/email/request` `{"email":"<user's own inbox>"}` | 200 in ~2 s and the email "Digital Wallet verification CONTINUE" arrives (Inbox). A Gmail failure would be 503. 60 s resend cooldown, 5 per 15 min. Only send to an inbox the user controls. |
| Telegram configured | `POST /api/v1/auth/telegram/native/start` `{"deviceFingerprint":"smoke","deviceName":"Smoke","deviceType":"ANDROID"}` | 200 with an `oauth.telegram.org/auth` URL and redirect `https://app937652339-login.tg.dev/tglogin`. Report only host/path, never `exchangeSecret`. Leaves one unused 5-minute flow. |

Never request, read or enter OTP codes, PINs or Telegram codes on the user's behalf.

---

## 8. Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| Crash `Connection to localhost:5432 refused` | `DB_*` variables missing/unresolved | §6.4; `DB_HOST` must resolve to `postgres.railway.internal`. |
| OTP request → 503 `OTP_DELIVERY_UNAVAILABLE` | Gmail token expired/revoked (`invalid_grant`) or wrong client (`unauthorized_client`) | Read the `GmailApiEmailService` log line; §6.6. |
| Log `MAIL_PROVIDER=gmail-api but [...] blank` | A Gmail variable is missing | §6.4. |
| Startup fails `app.mail.provider (MAIL_PROVIDER) must be smtp or gmail-api` | Typo in `MAIL_PROVIDER` | Fix the variable. |
| Telegram → `TELEGRAM_UNAVAILABLE` "not configured" | `TELEGRAM_*` missing or native redirect not `https://app<digits>-login.tg.dev/tglogin` | §6.4 with the values from `.env`. |
| Telegram approves but the app does not reopen | APK signed with a different key than the one Telegram's App Link knows | Rebuild on this workstation (§6.7); never reuse the `tg.dev` domain elsewhere. |
| Merchant App: `MERCHANT_AUTH_UNAVAILABLE` / shops stay `PENDING` | Profile is not `dev` | `SPRING_PROFILES_ACTIVE=dev`. |
| App shows signed-out or invalid-response after a URL change | Secure storage is per API URL | Sign in again. |
| `429` on sign-in or merchant starts from many testers at once | Per-IP limits may see Railway's proxy IP for everyone | Wait; optionally `SERVER_FORWARD_HEADERS_STRATEGY=native` (unverified). |
| Container restarts with `OutOfMemoryError` | Heap too large for the instance | Lower `MaxRAMPercentage` via a `JAVA_TOOL_OPTIONS` variable, or reduce `DB_POOL_MAX_SIZE`. |
| Every request slow (~0.2 s extra) | Region US East, users in Cambodia | Accepted for the run; moving region means recreating Postgres (data loss) — ask the user. |

---

## 9. History

- **7 Nov 2026 — Backend review fixes deployed from main (user authorized).** Audited committed
  snapshot from `c3957fc7785dedd2ba6e77d4a0f5bd66a03611af`: 278 files / 1,203,956 bytes,
  SHA-256 `cbb66365562007cfc18cb41c36b219797ed8c2a585dac0151912de52e217490b`.
  Dockerfile/.dockerignore/pom.xml/src only; no credentials/frontend/local outputs. Existing
  275/275 evidence applies to all 276 tested inputs after Git newline normalization.
  Explicit project/environment/backend selectors; new deployment `f97bf1e0-6079-4c16-9bd8-6bd14328a80b`
  SUCCESS. Source and all 20 migrations match `main`; schema V21 validated, no migration applied.
  Environment/service configuration, variables, domain, Postgres deployment/instance/volume
  and showcase unchanged. Healthy startup/Gmail provider and 200/401 HTTPS probes pass.
  Previous backend **`8fc7d198-bdc9-4a93-bd16-793b8c6b9668`** is the rollback reference.
  No DB recreation/mutation command, config change, APK build/install or authenticated/device
  payment acceptance. Records committed to `main` on 7 November.

- **6 Nov 2026 — Updated Customer and Merchant Railway APKs built (user authorized).** Sequential
  debug builds with the §6.7 flags succeeded (Customer Gradle 193.1 s, Merchant 160.1 s); Gradle
  daemons stopped after each. Includes all current uncommitted Flutter design work and Customer
  PIN Home preview. Both packages verified: expected application IDs, valid signatures matching
  the previous APKs, Railway URL present, old Wi-Fi address absent, no `.env` entries, latest design
  markers/assets present and ZIP CRC checks clean. All 550 recorded app/shared build inputs stayed
  unchanged during packaging. Build logs, source manifests and checksums:
  repository `.local/apk-refresh-20261106-055520/verification.json` and adjacent logs. Canonical
  copies and versioned copies match; previous APKs archived without deletion. Existing automated
  baselines remain Customer 298/298 and Merchant 119/119, both analyzers clean; not rerun for packaging.
  Read-only HTTPS probes: Swagger 200, unauthenticated accounts 401. No backend/configuration change,
  installation, authenticated device acceptance or payment performed.

- **6 Nov 2026 — PIN Home preview backend deployed (user authorized).** Full workstation backend suite
  **261/261**, then isolated allowlisted Docker build inputs uploaded explicitly to `backend`, project
  `superb-respect`, environment `production`. The repository contains unrelated uncommitted frontend
  work, so it was not uploaded wholesale and no commit was created. The snapshot matches all tested
  source hashes; credentials, local evidence, APKs and frontend files excluded. Base commit and complete
  manifest: backend `.local/railway-pin-preview-payload.json`; snapshot SHA above.
  Deployment `8fc7d198-bdc9-4a93-bd16-793b8c6b9668` **SUCCESS**; startup validated 20 migrations,
  schema V21 already current, no migration. Gmail API sender configured; URL/settings/secrets unchanged.
  HTTPS: Swagger **200**, foundation docs include `/api/v1/auth/pin/home-preview` with exactly the six
  preview fields, accounts without authentication **401**, preview with an invalid dummy ticket **401
  PIN_TICKET_INVALID**, `Cache-Control: no-store`. Postgres deployment remained unchanged and SUCCESS.
  Previous backend deployment: `1d35a295-87fb-4287-94b0-6a6798490069` (rollback reference).
  Logs: backend `.local/railway-pin-preview-{full-tests,build,startup}.log` and final status JSON.
  No APK build/install or authenticated customer/device test. Existing APKs still need a Customer App
  rebuild/install to show the new frontend PIN-preview experience.

- **5 Nov 2026** — Hosting chosen: Railway Trial (Render free rejected: blocks SMTP too, sleeps after 15 min, ~1 min cold starts). Gmail API sender added and live-tested locally (Inbox). Backend deployed with `railway up`; first upload went into the `Postgres` service by mistake (empty database, nothing lost; service recreated). Variables set from `.env` without printing. Flyway V1→V21 on an empty database. Live OTP email reached the Inbox. Debug APKs built against the Railway URL (first compile of the Merchant Kotlin). Native Telegram enabled on the server; device round trip not yet verified. Details: guide §8 entries of 5 Nov 2026.

### 6 November 2026 - Latest wallet/auth APK refresh

Both APKs rebuilt/verified after authorization; current canonical files now include linked merchant wallets and Merchant safe diagnostics/recovery, superseding earlier packaging-pending notes. Versioned copies `20261106-161530`; old APKs archived. All 550 sources unchanged; signing/package/content/CRC checks pass. Evidence repository `.local/apk-refresh-20261106-161530/verification.json`. Backend already current, no redeploy. No installation or real-user acceptance. See Customer §25, Merchant §20 and guide §8.
