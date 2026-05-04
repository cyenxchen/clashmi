# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Clash Mi — a cross-platform GUI client for Mihomo (Clash.Meta) proxy core, built with Flutter/Dart. The upstream app targets Android, iOS, macOS, Windows, and Linux; this open bridge branch currently has an Android-only MVP for running the core.

- Package name: `com.nebula.clashmi`
- Min Android SDK: 26 (Android 8.0)
- Deep link schemes: `clash://` and `clashmi://`

## Build & Run

Standard Flutter commands:
- `flutter run` — run on connected device
- `flutter build apk` — build Android APK (currently arm64-v8a while the open VPN bridge ships only arm64)
- `flutter pub get` — install dependencies
- `dart run build_runner build` — generate code (json_serializable, slang i18n)

Requires Java 17 for Android builds.

## Architecture

- **Manager-based modular pattern** — core logic in `lib/app/modules/` (ProfileManager, SettingManager, ClashSettingManager, etc.)
- **State management**: Provider
- **VPN service**: Native integration via `clashmi_vpn_service` (local sibling dependency at `../clashmi-vpn-service/`)
- **Mihomo core**: Android MVP uses the Go/gomobile core artifacts in `../clashmi-vpn-service/android/`, built from `cyenxchen/mihomo`
- **UI screens**: `lib/screens/` — 56+ feature directories
- **i18n**: 19 locales via slang, files in `lib/i18n/`

## Dependencies

Several packages are custom KaringX forks (referenced by git in pubspec.yaml):
- `flutter_inappwebview`, `android_package_manager`, `move_to_background`, `window_manager`

Do not suggest replacing these with pub.dev versions — they contain project-specific modifications.

The open `clashmi_vpn_service` bridge is currently Android-only and arm64-only;
iOS/macOS/Windows/Linux native bridge implementations still need to be added
before those platforms can run the core through this replacement.

## Android Signing

Release signing loads keystore from `../private/clashmi/android/sign/clashmi.release.keystore` via `android/key.properties`. The `private/` directory is gitignored.
