# Kesor Merchant — Feature List (brief for a redesign agent)

Written 4 November 2026. Describes what the **Merchant App already does**, screen by screen, and which rules a
redesign must not break. Visual reference: `Flutter Screen/Merchant App/` (28 screens, English, light, 393×852).
Technical detail: `docs/MERCHANT_APP.md`. Code: `frontend/merchant_app/lib/`.

## 0. How to use this brief

- **Free to change:** layout, visuals, navigation structure, icons, illustrations, copy tone, component styling,
  animation, tablet/landscape layouts.
- **Must keep:** every feature in §3, every state in §4, every rule in §5, English + Khmer, light + dark,
  accessibility (§6).
- **Not built (do not design as if it exists):** see §8.
- All data on screen comes from a backend. Redesign changes presentation only; no new API is available.

## 1. The app in one paragraph

Kesor Merchant is an Android-first Flutter app for a **shop owner**. The owner signs in only by approving in the
separate Kesor Bank (Customer) app, registers one shop that gets one KHR and one USD **business wallet**, collects
payments by showing a QR code that customers scan in Kesor Bank, sees confirmed sales, receipts and reports, and can
move money from a business wallet to their own personal wallet. Money is KHR (៛, whole units) and USD ($, two
decimals). Languages: English and Khmer. Themes: light, dark, system.

## 2. Screen map

Bottom navigation (4 tabs): **Home · Collect · Sales · More**. Everything else is a pushed page.

| # | Screen | Reached from | Screenshot |
| --- | --- | --- | --- |
| 1 | Welcome / Continue with Kesor Bank | App start when signed out | 01_Welcome… |
| 2 | Sign-in waiting for approval | Tap Continue | 02_Sign_In_Waiting… |
| 3 | Sign-in unavailable / denied / failed | Sign-in errors | 03_Sign_In_Service_Unavailable |
| 4 | Register shop (form, review) | First sign-in with no shop | 04_Register_Shop |
| 5 | Register shop — saved draft after uncertain result | Reopen mid-registration | 05_Register_Shop_Saved_Draft |
| 6 | Account recovery required | Owner has several legacy shops | 06_Account_Recovery_Required |
| 7 | Home | Tab 1 | 07_Home |
| 8 | Wallet details | Tap a wallet on Home | 08_Wallet_Details |
| 9 | Collect — enter amount | Tab 2 | 09_Collect_Enter_Amount |
| 10 | Collect — waiting for payment | Create QR | 10_Collect_Waiting… |
| 11 | Collect — payment received | Server confirms | 11_Collect_Payment_Received |
| 12 | Collect — request cancelled | Cancel | 12_Collect_Request_Cancelled |
| 13 | Collect — shop QR (reusable) | Collect → Shop QR | 13_Collect_Shop_QR |
| 14 | Sales (list, filters, totals) | Tab 3 | 14_Sales |
| 15 | Sales — empty | No sales in filter | 15_Sales_Empty |
| 16 | Receipt | Tap any sale, paid request or wallet QR row | 16_Sales_Receipt |
| 17 | Reports — daily / 18 monthly | Sales → chart icon | 17_…, 18_… |
| 19 | Payment requests history | Sales → Requests | 19_Payment_Requests_History |
| 20 | More (settings) | Tab 4 | 20_More_Settings |
| 21 | Shop profile edit | More → shop row, Home → Edit shop | 21_Shop_Profile_Edit |
| 22–25 | Owner transfer: amount, waiting, completed, failed | Wallet details → Transfer to my wallet | 22…25 |
| 26 | In-app payment alert banner | New payment while app is open | 26_Payment_Alert_Banner |
| 27 | Shop suspended / restricted | Server status | 27_Shop_Suspended_Restricted |
| 28 | Shop pending review | Server status | 28_Shop_Pending_Review |

## 3. Features

### F1. Sign-in with Kesor Bank
- One button: **Continue with Kesor Bank**. No email, password, phone or PIN in this app. Never show a PIN field.
- Opens the Customer app; the owner approves there with their PIN; Merchant receives the result automatically.
- Waiting state: explanation, progress, **Open Kesor Bank** (re-open) and **Cancel**.
- Distinct failure states: offline, service unavailable, denied by owner, expired, Kesor Bank app missing, cancelled.
- Session restores on reopen without asking again. **Sign out** ends only the Merchant session.
- Welcome also holds language (EN/KM) and theme toggles.

### F2. Shop registration
- Fields: shop name (required), business category (list of 11: Food & drinks, Grocery, Retail, Fashion, Beauty,
  Electronics, Health, Services, Education, Transport, Other), business phone (Cambodian formats accepted),
  city/province (25 locations, bilingual), shop address, description (optional), logo (optional, JPG/PNG ≤ 5 MB;
  shows the shop initial until a logo exists).
- Review step before submitting. Submitting creates the shop **and both wallets** at zero balance.
- Safe against double taps, lost responses and app restarts: the draft is saved before sending; an uncertain
  result shows a locked draft with **Check registration status** or **Discard and edit** — never silently resubmit.

### F3. Home (dashboard)
- **Shop card:** logo/initial, shop name, category, Merchant ID (`MCH-…`), status chip (Active / Pending / Suspended).
- **Action tiles:** Collect (primary), Sales, Edit shop.
- **Today's collections:** per currency — total received today and payment count. Distinct from balances.
- **Business wallets:** two cards (Khmer Riel wallet, US Dollar wallet): name, copyable account number, balance.
  Tap opens Wallet details. Refresh control.
- **Recent payments:** latest confirmed payments (payer first name + masked account, time, +amount). Tap → Receipt.
- Pull to refresh. Tablet uses a wider layout.

### F4. Wallet details
- Large balance card (copyable account number), **Transfer to my wallet** button (see F9), and read-only activity
  list (QR payments with payer, transfers, deposits), 20 per page, tap a QR row → Receipt.

### F5. Collect payments (QR)
- **Mode switch:** *Enter amount* (one-time QR) / *Shop QR* (reusable QR).
- **Enter amount:** currency KHR / USD, amount (hero-size input), optional order note (≤ 50 chars), **Create QR**.
- **Live request:** QR card (shop name, QR, amount, order note), status *Waiting for payment*, **5-minute countdown**
  from the server clock, request reference, **Cancel request**. The app checks status every 2 seconds.
- **Outcomes (each its own state):** *Payment received* (amount, payer first name + masked account, amount the
  customer paid in their currency, order note, transaction reference, time; actions **Open receipt**, **New payment**),
  *Cancelled* ("No money was received"), *Expired*, and *status unavailable* (retry).
- A paid request wins any race with cancel/expiry: if the payment landed, the app shows it as paid.
- The active request is remembered, so reopening the app resumes it.
- **Shop QR:** per currency, shop-branded QR card, **Save to gallery**, **Share**, note that customers enter the
  amount themselves and the owner should check Home before handing over goods.
- Suspended/pending shops cannot create QR codes (clear message).

### F6. Sales history
- Period chips: Today, Yesterday, 7 days, This month, Custom (date-range picker). Currency: All / KHR / USD.
  Search (reference or order note, debounced).
- **Summary card:** totals for the active filter per currency + count (covers the whole filter, not just the page).
- List grouped by **business day** (Phnom Penh); each day header shows loaded count and sums labelled *shown*.
  Rows: QR payment icon, payer + masked account, time, +amount. Infinite scroll + Load more + pull to refresh.
- Header links: **Reports** and **Requests**. Empty, loading, error and offline states; a rare
  "someone else updated, Try again" notice.

### F7. Receipt
- Navy header (shop name, "Payment received", amount received) and details: payer (first name + masked account),
  customer-paid amount, order note, transaction reference, time (UTC+07:00), request reference, exchange rate
  (`1 USD = 4,000 ៛`), receiving wallet.
- Actions: **Save to gallery** (PNG), **Share receipt** (PNG + text), **Copy reference**.
- Receipts are snapshots: editing the shop later never changes old receipts.

### F8. Reports and request history
- **Reports:** Daily / Monthly toggle, one currency at a time (KHR / USD, never combined), date-range picker,
  bar chart (zero-filled), table of period / payment count / gross, banner "Collections are payments received,
  not profit."
- **Requests:** history of QR requests with status chips Waiting / Paid / Expired / Cancelled, status filter,
  paging. Paid → Open receipt; Waiting → Open in Collect.

### F9. Owner transfer (business wallet → owner's own personal wallet)
- Entry: Wallet details → **Transfer to my wallet** (hidden/disabled when balance is zero or shop is not active).
- **Amount screen:** wallet name, available balance, amount, **Continue**; note "money goes to your own wallet in
  Kesor Bank in the same currency; you approve it with your PIN in Kesor Bank". The destination is chosen by the
  server, never typed.
- **Waiting:** countdown, **Continue in Kesor Bank** (opens the Customer app to approve), **Cancel**.
- **Results (separate states):** Completed (amount, from business wallet, to your wallet •••• 5678, reference),
  Denied, Cancelled, Expired, Failed — insufficient funds ("Nothing was moved").
- Only one open transfer at a time; reopening the app resumes it; the final answer always comes from the server.

### F10. Live payment alerts
- While the app is open and resumed: a top **banner** "Payment received · +25,000 ៛ from Sophea" (or "N new
  payments received"); tap → Sales; dismiss with ✕. Optional system sound and vibration.
- Payments made while the app was away alert on return. Old payments never alert at first load.
- Settings (More → Payment alerts): **Sound** and **Vibration** switches (default on) and the honest note
  "Alerts work while Kesor Merchant is open. Background notifications are coming later."

### F11. Shop profile
- Edit name, category, phone, city, address, description, logo (change/remove). Version conflict message if edited
  elsewhere. Blocked with a message when the shop is suspended/inactive. Never changes the owner's personal profile.

### F12. More (settings)
- Shop profile row, **Language** (English/Khmer), **Appearance** (System/Light/Dark), Payment alerts (F10),
  **Support** (email shown with copy), **Sign out**.

### F13. Shop status handling
- **Active:** everything works. **Pending review / Suspended:** read-only — Home, wallets, sales and receipts stay
  visible, QR creation and transfers are disabled with a visible reason and "Contact support".
- **Recovery required:** a full-screen message ("needs support review") with Sign out only.

## 4. States every screen must handle

Loading (never show fake zeros), empty, offline, server error with retry, stale-data marker when a refresh fails,
**uncertain** (request sent but answer lost — show "check status", never offer a blind resend of money actions),
expired session (back to Welcome), session revoked, and per-feature states listed above.

## 5. Rules a redesign must not break

1. **Money:** KHR whole units with ៛, USD two decimals with $; the two currencies are never added together; a
   missing/failed balance shows "unavailable", never 0.
2. A **sale** is only a confirmed QR payment. Deposits, owner transfers and unpaid requests are not sales.
   Collections are labelled "received", never profit.
3. "Payment received" appears **only** after the server says paid. A screenshot or banner is not proof.
4. The Merchant app never asks for, shows or stores a PIN or a Customer token. PIN approval happens in Kesor Bank.
5. Owner transfer destination is server-chosen; the owner cannot type an account.
6. Day boundaries are Asia/Phnom_Penh (UTC+07); show times that way.
7. Receipts and sales show only a payer first name and masked account — never more payer data.
8. Never auto-resend money-moving requests after an uncertain result; resume via status check.
9. Private data is cleared on sign-out/owner change; pushed pages close when the session changes.
10. Privacy cover hides content when the app is inactive/backgrounded.
11. Suspended/pending shops are read-only for collecting and transferring.

## 6. Accessibility and platform requirements

English + Khmer on every string; light + dark; text scale up to 2× without clipped controls (long content
scrolls); 48 dp minimum touch targets; screen-reader labels on icon-only buttons and amounts; reduced-motion
respected; safe areas and gesture bar; phone portrait first, plus 320 px wide, landscape and tablet (800 and
1280 px) layouts. Android first; iOS not accepted yet.

## 7. Current visual language (starting point, may be redesigned)

- Kesor identity: **gold** (primary actions), **navy** (emphasis surfaces, gradient shop and receipt cards with a
  faded Kesor mark), light-blue-grey surface cards (20 px radius), status chips (green Active/Paid, blue Waiting,
  amber Cancelled, red Suspended/errors), red "Kesor Merchant QR" header on QR cards with white QR tile on a dark
  card (dark QR modules on white — inverted QR codes scan badly).
- Fonts: Poppins (English), Google Sans (numbers/UI), Noto Sans Khmer. 20 px side gutters.
- Shared with the Customer app through `frontend/packages/kesor_design_system` (theme, tokens). The Customer app
  uses the same brand; decide with the owner whether the Merchant app must keep matching it.
- Shared building blocks: SurfaceCard, NavyCard, SectionTitle, ActionTile, CircleAction, StatusChip,
  CurrencyBadge, NoticeBanner, AmountText, KesorQrCard, ReceiptLines, ActivityRow, ReceiptRow.

## 8. Not built (out of scope for the redesign)

Background push notifications and voice announcements; cashiers/staff accounts; refunds; shift closing;
CSV/Excel export; multiple branches or counters; invoices and payment links; AI sales assistant; KHQR/Bakong or
any external-bank payment acceptance; withdrawal to a bank; currency conversion between wallets; separate Merchant
login or PIN; tablet-specific navigation rail. The **Customer app** is a different app and is not part of this brief.

## 9. Reference and how to verify a redesign

- Screens to match feature-for-feature: `Flutter Screen/Merchant App/` (and `Merchant App v2/`).
- Code map: `lib/features/{auth,shop,collect,sales,feed,transfer}`, shared UI in `features/shop/shop_widgets.dart`,
  strings in `core/merchant_strings.dart` (`t(context, en, km)`).
- Tests and screenshots (run in `frontend/merchant_app`, one at a time):
  `flutter analyze` · `flutter test test --concurrency=1` · `flutter test tool/screen_catalog.dart --concurrency=1`
  (renders every screen in light/English) · `flutter test tool/merchant_visual_qa.dart --concurrency=1`
  (232 renders: both languages, both themes, small phone, 2× text, landscape, tablets).
- Add any new screen to both fixtures. Do not remove or weaken existing tests to pass a redesign.
- Not verified on a physical device: shop registration onward, Android link handoff for owner transfers, sound,
  vibration, native sharing, restore after process death.
