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
