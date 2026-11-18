# Hybrid Note

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Building the portfolio demo

The demo for lucasyonghao.com/demos/hybrid-notes/ (DEMO_BUILD=true) is built
with `tool/build_demo_web.ps1`, on Windows PowerShell 5.1 or pwsh:

    $env:RECAPTCHA_SITE_KEY = '<public reCAPTCHA site key>'
    powershell -ExecutionPolicy Bypass -File tool/build_demo_web.ps1 [-Flutter path\to\flutter.bat]

It runs `flutter build web --release --base-href /demos/hybrid-notes/
--no-web-resources-cdn --dart-define=DEMO_BUILD=true
--dart-define=RECAPTCHA_SITE_KEY=...` into build/web and deletes the unused
flutter_service_worker.js. For that build only, a temporary
pubspec_overrides.yaml swaps google_sign_in_web for the do-nothing stub in
tool/demo_stubs/, so the demo never loads accounts.google.com/gsi/client.
The script always removes the file, puts pubspec.lock back and runs
`flutter pub get`, so real builds (Android, real web) are unchanged. When
google_sign_in_web is upgraded, update the stub's version to match.
