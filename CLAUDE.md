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

Requires Java 17 for Android builds. Android build pins NDK `28.2.13676358` and `compileSdk/targetSdk = 36` (`android/app/build.gradle.kts`).

## Architecture

- **Manager-based modular pattern** — core logic in `lib/app/modules/` (ProfileManager, SettingManager, ClashSettingManager, etc.)
- **State management**: Provider
- **VPN service**: Native integration via `clashmi_vpn_service` (local sibling dependency at `../clashmi-vpn-service/`)
- **Mihomo core**: Android MVP uses the Go/gomobile core artifacts in `../clashmi-vpn-service/android/`, built from `cyenxchen/mihomo`

### 本地依赖链(同一父目录中并存)

```
clashmi (本仓库, Flutter app)
  └─ pubspec.yaml: path: ../clashmi-vpn-service/   ← 路径依赖
       clashmi-vpn-service (Flutter plugin)
         └─ core/mihomo  ← git submodule,指向 cyenxchen/mihomo (Meta 分支)
              ⇕ 与同级 ../mihomo 工作副本同源(同一 cyenxchen/mihomo fork)
```

调试或排查内核/桥接层问题时,通常需要同时打开 `../clashmi-vpn-service` 与 `../mihomo` 两个仓库;`../mihomo` 改动需先推到 `cyenxchen/mihomo` Meta 分支,再在 `clashmi-vpn-service` 中 `git submodule update --remote` 同步,最后才会反映到本 app。
- **UI screens**: `lib/screens/` — flat layout (screens are top-level `.dart` files) plus `extension/` and `widgets/` subfolders
- **i18n**: 9 locales via slang in `lib/i18n/` (ar, en, es, fa, ja, ko, ru, zh-CN, zh-TW)

## Dependencies

Several packages are custom KaringX forks (referenced by git in pubspec.yaml):
- `flutter_inappwebview`, `android_package_manager`, `move_to_background`, `window_manager`

Do not suggest replacing these with pub.dev versions — they contain project-specific modifications.

The open `clashmi_vpn_service` bridge is currently Android-only and arm64-only;
iOS/macOS/Windows/Linux native bridge implementations still need to be added
before those platforms can run the core through this replacement.

## Android Signing

Release signing loads keystore from `../private/clashmi/android/sign/clashmi.release.keystore` via `android/key.properties`. The `private/` directory is gitignored.

## CI / Release

`.github/workflows/android-release.yml` builds the signed Android arm64-v8a APK and publishes GitHub Releases. It can be triggered by production tags (`v*`), `repository_dispatch` from `clashmi-vpn-service`, manual `workflow_dispatch`, or the scheduled upstream sync. Non-tag releases auto-generate a monotonically increasing `v<build-name>+<build-number>` tag so Android updates can install over the previous build.

The workflow runs `flutter analyze`, builds with explicit `--build-name` / `--build-number`, signs with `ANDROID_KEYSTORE_BASE64`, and uploads both the APK and a `.sha256` sidecar. Scheduled upstream sync merges `KaringX/clashmi@main`; merge conflicts stop the release and create an issue.

## AI Tool Configs

`AGENTS.md` at the project root is a symlink to this file — edit `CLAUDE.md` only. `analysis_options.yaml` is the Dart/Flutter lint config.
