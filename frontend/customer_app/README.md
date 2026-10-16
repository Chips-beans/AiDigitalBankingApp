# Digital Banking Customer App

Flutter customer application for AI Digital Banking and Smart Wallet.
The project currently contains the generated Flutter starter app. Banking screens
and Spring Boot API integration are the next implementation steps.

## Run locally

Install Flutter with its bundled Dart SDK and configure a target device or browser.
From the repository root:

```powershell
cd frontend/customer_app
flutter pub get
flutter devices
flutter run
```

To run in Chrome:

```powershell
flutter run -d chrome
```

## Project structure

- `lib/main.dart`: application entry point and starter screen.
- `test/widget_test.dart`: generated widget smoke test.
- `pubspec.yaml`: package metadata, SDK constraint, and dependencies.
- `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`: platform projects.

The package name is `customer_app`; the organization is `com.bank`.

## Verify

```powershell
flutter analyze
flutter test
```

## Backend

The Spring Boot project is located at `../../backend/digital-banking`.
The backend API uses the `/api/v1` prefix and defaults to port `8080`.
This starter does not yet make API requests.

## API environment

Phase 0 adds `lib/core/config/app_config.dart`, validated at startup. Android
development uses `http://10.0.2.2:8080/api/v1`; other targets use
`http://localhost:8080/api/v1`. Override this for physical devices:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.25:8080/api/v1
```

Replace the address with the backend computer's LAN address. For browser testing,
use `flutter run -d chrome --web-port=8081` to match the default backend CORS origin.
Release configuration requires an HTTPS API URL. See
[Phase 0 documentation](../../docs/PHASE_0_IMPLEMENTATION.md) for details.
