# Android Release Build Compatibility Plan

> **For agentic workers:** Execute this plan inline in the existing branch; do not reset or clean the workspace.

**Goal:** Make `flutter build apk --release --split-per-abi` succeed on the installed Flutter 3.47.2 while preserving app features and local work.

**Architecture:** Keep Flutter and application dependencies unchanged. Move the Android toolchain to the compatible stable stack AGP 8.11.1, Gradle 8.14, Kotlin Gradle Plugin 2.2.20, and remove AGP 9-only toggles. Do not patch Pub cache files; AGP 8 avoids the AGP 9 rejection of the plugin's existing ProGuard configuration.

**Tech Stack:** Flutter 3.47.2, Dart 3.13.2, Android Gradle Plugin, Gradle Wrapper, Kotlin Gradle Plugin.

**Spec:** User-provided task in `C:/Users/Thyag/.codex/attachments/f2a1e540-e188-458b-b151-caf93c498006/Texto colado.txt`.

## Global Constraints

- Preserve all existing app features and the current branch's commits.
- Do not edit the global Pub cache, commit build output, push, or delete stashes.
- Keep Android SDK/API 36 and JDK 17 compatibility.
- Run `flutter pub get`, `flutter analyze`, `flutter test`, then the split-ABI release build.

## Review Focus

- AGP 8.11.1 accepts compileSdk/API 36 and requires Gradle 8.13 or later.
- Flutter 3.47.2 requires Gradle 8.14 or later; Kotlin 2.2.20 supports Gradle 8.14 and AGP 8.11.1.
- The resolved in-app WebView plugin builds without changing cached sources.
- Release shrinking and each split ABI package complete successfully.
- Generated plugin registrants and other-platform files are preserved and reviewed.

## Tasks

### Task 1: Pin the supported Android toolchain

**Files:** Modify `android/settings.gradle.kts`, `android/gradle/wrapper/gradle-wrapper.properties`, and `android/gradle.properties`.

- [ ] Set AGP to `8.11.1`, KGP to `2.2.20`, and Gradle Wrapper to `8.14`.
- [ ] Remove AGP 9-only `android.newDsl` and `android.builtInKotlin` toggles.
- [ ] Confirm the cache plugin source remains unchanged and has no BOM.

### Task 2: Verify the complete app build

**Files:** Review generated changes only; do not alter app feature code for unrelated reasons.

- [ ] Run `flutter pub get`.
- [ ] Run `flutter analyze` and `flutter test`.
- [ ] Run `flutter build apk --release --split-per-abi` and investigate the first failing Gradle cause if needed.
- [ ] Record APK paths/sizes and review final Git status, preserving pre-existing local changes.
