# Email authentication screens

Implemented 30 October 2026 from live Kesor Figma section `253:1457`:

- `252:150`: email entry.
- `256:150`: email verification.
- `258:150`: create profile.

The Figma connection was restored and high-fidelity design context, measurements,
screenshots, typography and original SVG exports were read for all three frames.
Reference size is 440 × 956. Email fields begin at (24,147), inputs are 56px high,
primary buttons 54px high, and inputs/buttons have 16px radii. The profile photo
card is 392 × 112. Colors and Poppins/Google Sans/Khmer fonts reuse the existing
design system. Source-specific SVGs are bundled under `assets/auth/email-*`.

`EmailAuthLayout` provides the responsive frame, navigation, preferences and legal
footer. Email entry retains the existing continuation and email-linking APIs.
`EmailOtpField` uses one native editable field behind six visual slots, retaining
paste, selection, keyboard navigation, OTP autofill and digit filtering. Resend
and expiry use server-provided timing rather than the illustrative Figma 3:00.
The delivery email is masked. New/returning routing remains unchanged.

Profile creation retains server-side onboarding enforcement and name validation.
The checkbox gates submission in the UI; this is not a new server-side legal
acceptance ledger. Legal links open the existing short informational policy
dialogs; operator-approved complete legal policies remain future work. The
Figma label “Create Account” completes a customer profile only. It does not open
or fund any financial account. The profile back control signs out and preserves
the server-side incomplete profile for the next verified continuation.

English/Khmer and light/dark preferences continue across screens. Figma provides
light English frames here; dark and Khmer are adaptations using existing tokens.
Small widths and large text stack the name fields and photo details. Content,
footer and focused controls scroll above the keyboard. Hit targets extend beyond
small source artwork. Native builds use their OS status bars. `showDeviceChrome`
is an explicit rendering-fixture option only; it uses exported device artwork and
bundled Google Sans as the available stand-in for the source SF Pro clock font.

## Persistent profile photo

The user explicitly requested real backend persistence, not a local preview.
The OS file selector accepts JPG/PNG. Without a photo, the avatar uses the first
grapheme of the entered first name (or last name while first name is empty),
updating as the customer types. Latin initials are uppercased; Khmer combining
characters stay together. Before a name is entered, the neutral person icon stays.
Selected image bytes display immediately while the authenticated upload runs,
with localized uploading feedback. On success, the server-confirmed normalized
image replaces the preview. An unsaved preview is never stored as a saved photo.
Profile also displays the saved avatar and permits replacement after onboarding.
Cancelled selection sends no request. Read failures can be retried; failed
replacement retains the previously confirmed image. Session changes clear cached
photos and suppress late responses. Local previews also clear on privacy cover,
PIN lock, logout or session replacement. Mutations are not replayed automatically.

Authenticated endpoints (same response envelope as other authentication routes):

- `GET /api/v1/auth/profile/photo`: own photo with `contentType` and `imageBase64`;
  an absent photo returns success with no `data` member.
- `PUT /api/v1/auth/profile/photo`: multipart part `photo`; returns the saved photo.

There is no customer-ID input or public image URL. Verified incomplete customer
profiles may upload before completing their names; staff identities are rejected.
Responses disable caching. Uploads are limited to 5 MiB and 16 megapixels. The
server detects the decoded format rather than trusting MIME/filename, checks
dimensions before decoding, normalizes to at most 1024px on the longest edge,
re-encodes without input metadata, and rejects malformed, SVG and GIF content.
The per-customer upsert and audit event share a transaction. Photos live in a
separate PostgreSQL `customer_profile_photos` table, introduced by additive V12.
No existing migration or financial table was changed.

The source schema is now V12 (27 foundation API paths). The existing development
database remains V11: it was not started or migrated during this task. Its next
normal backend startup applies V12. Tests use isolated embedded PostgreSQL/local
SMTP; no real email, customer operation or financial posting was performed.

## Verification

- Backend: 117 tests passed, including upload validation, ownership, missing
  authentication, staff exclusion, actual decoded MIME, normalization, rejected
  oversized input, saved-image preservation and persistence across server restart.
  Existing migration/restart, auth, analytics and banking regression checks pass.
- Flutter: 139 checks passed (138 tests plus the email-auth rendering fixture).
  Covers the complete continuation journey, invalid codes, names, back behavior,
  large text/reduced motion, accessible navigation targets, multipart API behavior,
  photo failures, reauthentication reload and late response suppression after logout.
- Flutter analysis: no issues. API-mode web build and Wasm dry run succeeded.
- The normal-entrypoint Android debug APK built with `APP_ENV=dev` and
  `API_BASE_URL=http://127.0.0.1:8080/api/v1`. No emulator/device installation was
  performed. The previous Analytics APK is superseded by this build.
- `tool/email_auth_visual_qa.dart` renders all three screens in both themes and
  languages, 375px width, 2× text, landscape and tablet sizes. Screenshots and logs
  are ignored under `.local/qa/email-auth/` and `.local/email-auth-*`.

These are Flutter-rendered fixtures, not screenshots of a successful personal
login. OS file-picker interaction and the complete live photo flow still require
physical-device acceptance. iOS/macOS builds were not run on this Windows host.
The file-selector dependency includes generated plugin registration; macOS has
the package-required user-selected-file read entitlement.
