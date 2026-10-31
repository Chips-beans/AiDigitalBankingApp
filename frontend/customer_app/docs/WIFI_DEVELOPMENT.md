# Customer App over Wi-Fi

Verified 31 October 2026, Asia/Phnom_Penh.

## Current build and connection

- PC Wi-Fi IPv4: `172.16.128.192/20`.
- Backend URL compiled into the new APK:
  `http://172.16.128.192:8080/api/v1`.
- Backend remains running on 8080, Java PID 18612; no restart, configuration,
  database migration or financial change was performed for this task.
- `KesorBank-WiFi-Test.apk` is a normal-entrypoint Customer API/dev debug build.
  It includes the existing scanner changes and shared Kesor theme integration.
- APK: 245,289,202 bytes; SHA-256:
  `badef91fb842cfb2d7a1dfde8b215e353f37dd3706a5ef1c6858ca79ca4cb087`.
- Signing certificate matches the previous development APKs. No app data was
  cleared or application uninstalled. This APK was delivered, not installed by
  the agent during this Wi-Fi task.

## Firewall verification

Windows Firewall is enabled and the Wi-Fi profile remains Public. Existing
enabled inbound `Java(TM) Platform SE binary` Public rules already permit TCP
and UDP traffic for `C:\Program Files\Java\jdk-24\bin\java.exe`.
Those existing rules have Any local/remote address and port scope. They were
left unchanged; no additional rule, UAC elevation, profile change or firewall
disable was necessary to make the requested Wi-Fi connection work.

A narrowly scoped preparation script was drafted but not executed; it is retained
in this chat's `work/Enable-Kesor-WiFi.ps1`, not a claim of an active new rule.
This task verified existing access; it did not narrow the existing Java rules.

## Real phone network check

A connected TECNO LJ6 had Wi-Fi address `172.16.128.213/20`. A read-only HTTP
request to `/api/v1/accounts/me`, bound to that phone Wi-Fi source address,
returned `HTTP/1.1 401` with `AUTHENTICATION_REQUIRED`.

The device route was `172.16.128.192 dev wlan0 ... src 172.16.128.213`.
ADB was used only to execute the diagnostic on the connected phone; the HTTP
connection used Wi-Fi to the PC LAN address, not `adb reverse` or a USB tunnel.
No customer authentication or payment was submitted. This establishes Wi-Fi
reachability; personal in-app sign-in remains a user action after installation.

## Install and use without USB debugging

1. Download `KesorBank-WiFi-Test.apk` from this chat's outputs and transfer it to
   the phone/tablet using Quick Share or another normal file-transfer method.
2. Open the APK on Android and install it as an update to preserve existing data.
3. Keep the PC/backend running and both devices on the same Wi-Fi.
4. Open Kesor Bank and use the existing account. Changing the API origin changes
   the secure-session namespace, so the app may ask for sign-in again. Accounts,
   balances and history are still on the same backend database.

Browser connection test:
`http://172.16.128.192:8080/api/v1/accounts/me`.
An authentication-required/401 response is expected without a signed-in session.

If the PC Wi-Fi address changes, rebuild with its new address. No router port
forwarding was configured. Runtime Wi-Fi access needs no USB debugging or USB
forwarding after installing this build.

## Rebuild and evidence

From `frontend/customer_app`, sequentially:

```powershell
flutter test test/app_config_test.dart --concurrency=1 --no-pub
flutter build apk --debug --no-pub --dart-define=APP_ENV=dev --dart-define=APP_MODE=api --dart-define=API_BASE_URL=http://172.16.128.192:8080/api/v1
```

Five configuration tests passed. Android build succeeded. APK inspection verified
the LAN URL in the compiled Dart kernel and found no `.env` files. Gradle daemon
was stopped after packaging. No full financial regression was repeated because
this task changed only build-time configuration and documentation.

Build log: `.local/customer-wifi-build.log`. Safe build/network verification JSON
is in this chat's `work/wifi-build-verification.json` and
`work/wifi-connectivity-verification.json`.

APK and user-facing setup notes:
`C:\Users\User\Documents\Codex\2026-10-31\kesor-bank-is-a-digital-banking\outputs`.
