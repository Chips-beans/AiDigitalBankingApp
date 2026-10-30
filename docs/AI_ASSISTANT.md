# Core customer AI assistant

Current runtime/acceptance status (31 October 2026): the user configured a Gemini
key and enabled both flags on 30 October. A successful live Gemini answer and
Khmer prose quality have **not** been verified. Configuration availability is not
provider health. Defaults described below are source defaults; consult
`NEXT_SESSION_BRIEF.md` for the consolidated handoff. Keep all key values private.

### Live provider check — 31 October 2026 (Phase 2 of `IMPLEMENTATION_PLAN.md`)

Result: **the live assistant does not answer; the Gemini provider never returns
generated content for the configured key.** No code or `.env` value was changed.

- Backend config (via the Dotenv loader): `GEMINI_ENABLED=true`,
  `GEMINI_CUSTOMER_CONTEXT_ENABLED=true`, `GEMINI_MODEL=gemini-3.8-flash`, key
  present (value not printed).
- `GET /v1beta/models/gemini-3.8-flash` with the key: **200** (model exists, supports
  `generateContent`). Model listing also succeeds, so the key is accepted.
- `POST …:generateContent` with a synthetic, non-customer prompt: connection in
  ~0.2 s, then **0 bytes within 20 s, 45 s and 60 s** — with and without the
  backend's own `thinkingConfig`, from both PowerShell and curl. `gemini-flash-latest`
  and `gemini-3.7-flash` behave the same. A retired model (`gemini-2.5-flash`) returns
  a 404 in 0.5 s, so POST traffic does reach Google; the stall is provider/project
  side for accepted generation requests.
- Runtime logs: every real device assistant turn (30 October 17:34, 17:39, 17:40,
  23:25) ended `AI_TIMEOUT` after ~10 s, the adapter's read budget. No successful
  live Gemini answer exists in any log.
- Consequence: intent extraction is the first provider call and has no local
  fallback, so customers get `AI_TIMEOUT` and no cards. The `FALLBACK` path only
  covers a failed second (explanation) call. English/Khmer answers, refusal of
  payment requests and explanation fallback could not be exercised live.

Next: check the Google AI Studio / Cloud project for this key (billing, quota,
rate-limit or project status), or try a newly issued key; then rerun the probes.
The provider's 404 text recommends its newer Interactions API — whether
`generateContent` is restricted for this project is unconfirmed.

### Second check — new key, 31 October 2026 ~02:00

The user replaced the key. With it, model listing works, but `gemini-3.8-flash`,
`gemini-3.7-flash` and `gemini-flash-latest` still stall (one reply was **503
"currently experiencing high demand"** after 42 s), so the earlier failure was most
likely provider capacity, not the old key. `gemini-3.5-flash-lite` answered in
2.4–3.6 s with correct Khmer, including with the backend's `thinkingLevel=low`
config. At the user's request `.env` now sets `GEMINI_MODEL=gemini-3.5-flash-lite`
(only that line changed); the backend was restarted at 01:55 (Java PID 31644, log
`.local/gemini-backend-20261031.log`).

**First successful live turns (tablet, app language Khmer, locale `km`):** six
questions all `COMPLETED` in 0.8–3.3 s, no `AI_TIMEOUT` — live intent extraction works.

- Khmer balance request → two verified `BALANCE` cards, correct; Khmer reply.
  `explanationStatus=FALLBACK`: the optional second (explanation) call did not
  produce validated prose, so the localized fallback sentence was shown.
- Greeting, identity, "what can you help with", saving tips → `NOT_NEEDED`, no
  cards; the approved Khmer capability/limits text. Out-of-scope advice was
  correctly not given.
- "How can I scan a QR code?" → `HELP` card with the approved Khmer QR steps.
- English-language questions were answered in Khmer because the app locale was
  `km` (expected behavior; locale comes from the app language).

Still unverified: any `explanationStatus=AI` answer (Gemini prose), an `en` locale
turn, a monthly summary, and a payment-request refusal. The single explanation
fallback is unexplained (validation rejection vs. provider error is not logged).

The customer assistant is read-only. It interprets questions, retrieves the
authenticated customer's banking data, renders verified cards, and optionally
adds a short Gemini explanation. It cannot post a payment or prepare a payment
instruction. Existing transfers and QR flows retain their own confirmation and
recovery behavior.

## Available capabilities

- **Balances:** customer-wide USD/KHR totals and up to ten account links per
  currency. These are recorded balances, not a promise that frozen funds can be
  transferred. Selected-account queries recheck ownership.
- **Search:** date, currency, exact amount, incoming/outgoing direction, type,
  recorded status, reference and participating account number. Ownership is
  applied regardless of the submitted filter. Missing currency for an amount
  requires clarification. Default date range is the current banking month;
  explicit inclusive ranges are limited to 366 days.
- **Receipt details:** reuse the existing authorized reference lookup. A missing
  or inaccessible record returns 404. Recorded internal status does not establish
  external-bank settlement.
- **Monthly cash flow:** reuse Monthly Analytics, excluding transfers between
  accounts owned by the same customer. USD and KHR stay separate; totals include
  opening test deposits, whose amounts are additionally identified as test credits.
- **Help:** approved English/Khmer instructions in versioned
  `backend/digital-banking/src/main/resources/ai/kesor-help-v1.json`, covering
  accounts, manual transfers, receiving/scanning QR and PIN recovery.

New questions retrieve current financial data. Request retries return the
original saved snapshot and its timestamp. Follow-ups inherit validated filters;
an explicit new month replaces older search-date filters. Category spending,
budgets, saving goals, alerts, voice, external settlement, conversion and payment
preparation/execution are outside this version.

## Configuration and provider behavior

The ignored backend `.env` is the only local place for provider credentials;
never put them in Flutter, source control, screenshots or chat. No private
credential or ignored runtime `.env` assignment was changed during implementation;
the tracked `.env.example` documents the disabled defaults.

Source defaults are `GEMINI_ENABLED=false`,
`GEMINI_CUSTOMER_CONTEXT_ENABLED=false`, and
`GEMINI_MODEL=gemini-3.8-flash`. The model can be overridden. The separate context
flag is the operator's assertion that the project's billing and data handling
have been reviewed for customer context. Configure `GEMINI_API_KEY` and both flags
only after that review. This implementation does not provision a paid account,
verify billing automatically, or enable production deployment.

Gemini is called exclusively from Spring `RestClient`, using
`x-goog-api-key` and stateless Generate Content requests. Redirects are not
followed. Structured output is validated independently before any allowed tool
runs. The model cannot choose a customer ID, SQL, arbitrary URL or banking write.
There is no web search, vector store, agent loop or provider-managed conversation.

Each turn makes at most two provider requests: intent extraction, followed by an
optional explanation. The overall provider deadline is 25 seconds; individual
requests have a maximum ten-second read budget and a three-second connection
timeout. There are no automatic provider retries. Output is capped at 2,048
tokens/request and response bodies are bounded. At most two provider requests
run simultaneously per backend instance.

Default limits are 2,000 characters/question, ten new turns/minute/customer and
100/day/customer. Persistent usage windows are shared by the legacy AI routes.
Replay/status reads do not charge another turn. Rate errors include Retry-After.

Financial cards come entirely from backend data and exact decimal calculations.
Only necessary totals, dates, counts and statuses are supplied for explanations.
Full account numbers and transaction references use opaque aliases during intent
extraction. Profile names/email, recognized phone-like values, links and token
patterns are removed from conversational provider context. Clearly marked PIN,
OTP/password/token submissions are rejected before claim/history persistence;
customers are also warned against entering secrets. This detection cannot infer
every possible unlabelled secret in arbitrary text.

Explanations must reference verified fact placeholders rather than literal
numeric values, dates or identifiers. Unknown placeholders and unverified values
are rejected. If explanation validation or the second provider call fails, the
assistant returns the verified cards with localized fallback wording and
`explanationStatus=FALLBACK`. AI prose still requires live language/quality
acceptance; it is not a financial authorization or a guarantee of model accuracy.

## API contract

All new routes require customer authentication and use the standard
`{success,data,message,timestamp}` envelope. Responses use no-store caching.
Ownership is derived from the access token. Lists default to 20 items, with a
maximum of 50; history/search use descending timestamp/ID cursors.

| Route under `/api/v1` | Contract |
|---|---|
| `GET /ai/capabilities` | `available`, capabilities/locales, retention and limits. Availability indicates configuration, not a paid provider health probe. |
| `GET /ai/conversations` | `{items,nextCursor}`; optional `cursor,size`. Optional `requestKey` recovers a creation claim and returns the same page shape with one conversation, or 404. |
| `POST /ai/conversations` | Required Idempotency-Key, no body; returns a conversation with UUID, title and timestamps (201). |
| `PATCH /ai/conversations/{id}` | `{title}` up to 80 characters; returns the renamed conversation. |
| `DELETE /ai/conversations/{id}` | Deletes the owned conversation and contents; returns `{deleted:true}`. |
| `GET /ai/conversations/{id}/messages` | `{items,nextCursor}`; each item includes ID, question, locale, answer snapshot and creation time. |
| `POST /ai/conversations/{id}/messages` | Required Idempotency-Key and `{message,locale,context}`; locale `en`/`km`, context optional. Returns the saved turn, or 202 while the original turn is pending. |
| `GET /ai/conversations/{id}/requests/{key}` | Reads a request result without contacting Gemini. |
| `GET /transactions/search` | Filters `currency,accountNumber,month,from,to,amount,direction,type,status,reference,cursor,size,locale`. Returns items, verified cards, normalized filters and continuation cursor. Foreign account matches are empty. |

Question context accepts the same financial filter fields. Client-selected
account context must be owned. The intent parser can use participating account
aliases for searching the customer's own transaction records, which does not
provide a general account lookup.

A turn contains `requestId`, `status` (`PENDING`, `COMPLETED`, `FAILED`), `answer`
and `errorCode`. An answer contains `reply`, typed `cards`, `asOf` and
`explanationStatus` (`AI`, `FALLBACK`, `NOT_NEEDED`). Card types are `BALANCE`,
`MONTHLY`, `TRANSACTION`, `HELP`, `MORE`; each has title, label/value fields and
server-created actions. Allowed action types are `ACCOUNT`, `ACCOUNTS`,
`TRANSACTION`, `ANALYTICS`, `HELP_SCREEN` and `MORE`. Actions open existing
authorized screens or fetch another result page; model prose is never executable.

Failures use typed codes including `AI_UNAVAILABLE`, `AI_TIMEOUT`,
`AI_INVALID_RESPONSE`, `AI_RATE_LIMITED`, `AI_PROVIDER_RATE_LIMITED`, `AI_BUSY`,
`AI_SENSITIVE_INPUT`, `AI_IDEMPOTENCY_CONFLICT`, `AI_REQUEST_IN_PROGRESS` and
`AI_REQUEST_INTERRUPTED`. Missing/inaccessible resources return 404. Provider
failure text is not written as an assistant answer or new successful insight.

The legacy `/ai/chat` retains its request/response shape through the common
grounded engine, without persistent chat history or new-route replay guarantees.
Legacy spending insight routes remain separate, bounded and rate limited; their
client-supplied category reports are not used as verified assistant facts. Existing
historical insight rows are preserved.

## Persistence and recovery

Additive Flyway V15 adds `ai_conversations`, `ai_requests`, `ai_messages` and
`ai_usage_limits`. V1–V14 and financial history are unchanged. No ordinary
development backend startup or development migration is part of this task.

Creation and message keys are scoped to the authenticated customer. Message
fingerprints include the conversation, locale, context and immutable question.
Identical requests replay their original result; changed requests conflict. A
database constraint and short customer-scoped claim transaction permit one pending
turn per conversation. Claims commit before provider calls; network requests hold
no database transaction or row lock. Failures retain recoverable terminal status.

Status reads do not run Gemini. Pending requests older than two minutes are
reported interrupted and a minute maintenance task persists that result. Individual
messages/results expire after 30 days; expired messages are immediately invisible
and daily cleanup purges them and empty expired conversations. Deletion during a
provider request cannot restore content. A creation-key tombstone prevents an
old creation retry from recreating a deleted conversation during retention.

Flutter uses a dedicated 35-second AI client; ordinary banking retains its
12-second timeout. Before sending, native secure storage saves only the pending
question/key/locale/conversation, scoped by API/mode/customer. Full transcripts are
not cached locally. Browser/demo pending state is memory-only, and demo mode never
activates as an API-error fallback.

Lost creation responses recover via GET before offering explicit send. Lost
answer responses recover via status/history reads. Reopening, PIN unlock,
authentication failure and navigation never automatically resend a question.
An unknown-result retry uses the original key; a confirmed failed turn requires
an explicit new-key retry. The customer can dismiss local recovery with a notice
that an already sent question may still finish in server history.

Polling is every two seconds while the conversation is visible/unlocked, for at
most 30 seconds, followed by manual checking. Privacy cover, PIN lock, logout and
navigation stop polling and suppress late UI results. History/title dialogs hide
and dismiss on privacy transitions. Existing PIN and transfer journals are not
weakened or reused for chat.

## Verification and remaining acceptance

Evidence is ignored under backend `.local/assistant-*`, Flutter
`.local/assistant-*` and `.local/qa/assistant/`. Automated provider calls use a
deterministic fake or loopback HTTP server with synthetic data, never a paid/live
Gemini request. Backend tests use isolated PostgreSQL and local test mail.

The controlled customer acceptance opens funded pairs, transfers USD 10 and
KHR 10,000, and checks sender USD 190/KHR 90,000 and recipient USD 210/KHR 110,000
through verified assistant cards. Additional checks cover ownership, precision,
cursor pagination, duplicate claims, restarts, deletion, expiry, rate counters,
provider limits/failures, aliases and explanation validation. Flutter covers
request recovery, encrypted storage, history operations, routes, privacy/PIN,
keyboard, themes, languages and accessibility.

Final counts/build artifacts are recorded in CURRENT_PROJECT_HANDOFF.md. Live
Gemini interpretation/Khmer explanation quality and physical-device acceptance
remain pending until provider configuration/device access are available. Native
iOS verification still requires a Mac/device. No production-readiness or external
payment-settlement claim is established by these tests.
