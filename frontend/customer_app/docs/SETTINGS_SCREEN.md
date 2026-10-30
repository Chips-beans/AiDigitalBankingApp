# Settings

Reference: Kesor Bank Figma `320:308`, 440×999. The root screen uses the existing
floating bottom navigation and native system bars. It matches the 20px insets,
84px profile card, 16px radii, 20px group spacing, 64/60/56px rows, 48px sign-out
button and Poppins typography. Content scrolls with clearance for navigation;
larger text and Khmer can expand rows instead of clipping. The disabled
biometric row deliberately has no action and exposes disabled semantics.

The name and photo come from SessionController's authenticated profile. Without
a photo, the avatar uses the first name character, consistent with onboarding.
Personal details edits use `PUT /auth/profile/details`; they never repeat
onboarding or create accounts. Existing photo upload and verified identity
linking are reused. Name fields follow the API's 50-character limit.

`POST /auth/pin/change` requires an authenticated, unlocked customer session and
the current PIN. It uses the same peppered BCrypt hash and persistent shared
five-attempt counter as unlocking. On the fifth mismatch all of this customer's
PIN locks close. Success replaces the hash and revokes other sessions. Current
session tokens/ticket remain usable. No PIN is stored in preferences or logged.
The mutation is not automatically replayed. Backgrounding still locks the app.

Language supports English/Khmer, and appearance supports System/Light/Dark.
Selections and optional activity alerts are serialized to the existing device
preference store. Local Android alerts default off, require Android permission,
and are posted only after a verified transfer/account-opening success callback.
They contain no balances, amounts, names or account numbers. This is not a
background push notification service. Notification settings and a test alert are
available. Other platforms explain Android availability without fake switches.

Help provides English/Khmer FAQ, navigation to the read-only assistant and an
email composer for the user-specified `reachsteav2@gmail.com`; a copy-address
action handles devices with no mail app. Email is never automatically sent.
Terms/privacy are explicitly labeled demo data at the user's request, dated
31 October 2026. Sign-out confirms then reuses server revocation/vault clearing.

Settings subpages belong to the signed-in shell rather than independent routes,
so locking/sign-out removes profile forms and PIN entry controllers.

Checks:

```powershell
flutter test test/settings_test.dart --concurrency=1
flutter test tool/settings_visual_qa.dart --concurrency=1
flutter analyze
```

Visual fixtures use controlled demo data and write PNGs to ignored
`.local/settings-visuals/`. They cover English/Khmer, light/dark, narrow screens,
2× text, landscape, tablet and every Settings detail page. They never call a
live account or submit a payment.
