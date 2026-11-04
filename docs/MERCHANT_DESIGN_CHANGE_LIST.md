# Merchant App — Design Change List

**Design reviewed:** Figma "Kesor Bank", Section 1 (node 358:2726), 11 screens, English, light.
**Compared with:** the built Merchant App (`docs/MERCHANT_FEATURE_LIST.md`, screenshots in `Flutter Screen/Merchant App/`).
**Result:** the design covers about a third of our features and includes several we have not built.

## 1. REMOVE from the design (not built)

| Area | Remove |
| --- | --- |
| Outlets | Select Outlet sheet, "Current Outlet" switcher, Locations, Outlets tab, Open/Close toggles |
| Cashiers | Cashiers tab, "1 Cashier" labels |
| Cashback | Cashback tab, "Cash Back Promotion / Redemption" card |
| Analytics | Refunds, Void, Tip cards; Net sales; trend %; Popular Payment Methods (Bank Pay, KHQR, cards); Top Ranking Outlets; "Payment Type" filter |
| Receive | Payment Link, Offline Scan, "Request Printed QR" |
| Menu / header | Download Report, Invite Friends, notification bell (no push notifications yet) |
| Navigation | Center "Scan Receive" tab (Merchant does not scan) |
| Profile | Owner photo, personal name, "User ID", "Security" row (PIN lives in Kesor Bank), "Update" badge |
| Other | Terms & Conditions (nothing exists in Merchant; add a placeholder or drop), app version / last login / copyright footer |

## 2. ADD to the design (built, missing in the design)

| Area | Add |
| --- | --- |
| Sign-in | Welcome ("Continue with Kesor Bank"), waiting for approval, failure states (offline, denied, expired, app missing) |
| Registration | Register shop form (logo, name, category, phone, province, address), saved-draft state, Account Recovery |
| Shop status | Suspended and Pending-review screens (read-only, "Contact support") |
| Home | Two business wallets with balances (KHR, USD), today's collections per currency, shop card with status and Merchant ID, recent payments |
| Wallets | Wallet Details (balance, copyable account number, activity) with **Transfer to my wallet** |
| Owner transfer | Amount, Waiting for approval, Completed, Failed (4 screens) |
| Collect | After "Show QR": QR card + 5-min countdown + Cancel; states Payment received, Cancelled, Expired |
| Shop QR | Reusable QR per currency with Save and Share |
| Receipt | Receipt page with Save to gallery, Share, Copy reference |
| Sales | Totals summary, period chips, currency filter, search |
| Requests | Payment requests history with status filters |
| Reports | Daily/Monthly bars, one currency at a time, "payments received, not profit" note |
| Alerts | In-app payment banner; Sound and Vibration settings |
| Shop profile | Edit shop details and logo |
| Global | Khmer, dark theme, KHR/USD on every money screen, loading / empty / error / offline states |

## 3. ADJUST in the design

- **Navigation:** the design has a drawer + 3 bottom items; the app has 4 tabs (Home, Collect, Sales, More). Pick one structure.
- **Home tiles:** replace Transaction / Manage Business / Payment Link with **Collect / Sales / Edit shop**.
- **Analytics:** add a KHR/USD selector; use "collections", not "revenue".
- **Transaction History → Sales:** keep the date-grouped list; show payer first name + masked account.
- **Manage Business → Shop profile:** replace the outlet/cashier tabs with the shop-details form.
- **Receive Payment:** the design shows `$` only; the app needs a KHR / USD choice.

## 4. Decisions needed from the owner

1. **Brand:** keep Kesor gold + navy, or adopt the template's orange/red/grey?
2. **Calculator keypad** (+ − × ÷ =): keep it (new, small feature) or use a plain number pad?
3. **Navigation:** drawer + 3 items, or 4 tabs?

## Status — redesign built (4 Nov 2026)

Owner decisions: **Kesor gold + navy**, **side menu + Home / Collect / More**, **plain number pad**.
Built in Figma on the "Merchant App" page as section **"Merchant Redesign · Change list (Kesor)"**
(node `363:3084`, beside Section 1, which is unchanged): 28 English/light screens in four rows
(A sign-in & status · B home, menu, wallets, transfer · C collect & receipts · D sales, reports, settings)
plus local components (`v2/App Bar`, `v2/Bottom Nav`, `v2/Menu Row`, `v2/Payment Row`, `v2/Number Pad`,
`v2/QR Card`, icons) using the file's Kesor colour tokens, text styles and `Merchant/Button` / `Merchant/Status`.
Not done: Khmer and dark variants, prototype links, and tablet layouts.

**v2 · Quiet (4 Nov 2026)** — section `370:4356`, below v1, after feedback that type and colour were too
heavy and parts duplicated. Same 28 screens rebuilt with `q/*` components: Poppins Light (money),
Regular (text) and Medium (titles, buttons) only; white screens, flat surface groups, hairline dividers;
navy as text and small selection states only; gold only on the one primary button. Removed duplicates:
Home Collect button and Shop QR shortcut (Collect tab covers both), settings and sign-out in the side
menu (they live in More), repeated Active chips, amounts repeated inside buttons, Shop QR share icon
next to a Share button. Design notes moved below the screens.

## 5. Rules the designer must keep

Money is KHR (៛, whole units) and USD ($, two decimals), never added together. "Payment received" shows only after the server confirms. No PIN field anywhere in this app. Receipts show only payer first name + masked account. Suspended/pending shops are read-only. English + Khmer, light + dark, 48 dp touch targets, 2× text.
