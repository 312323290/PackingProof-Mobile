# Repository Guidelines

## Project Overview

PackingProof-Mobile is a Flutter app for continuous package-recording and shipping-label barcode marking. Android is the primary release target. Recordings, indexes, and settings are stored locally unless the operator explicitly configures LAN backup.

## Project Structure

- `lib/controllers/` contains recording and work-session state machines.
- `lib/services/` contains barcode recognition, persistence, speech, order receiving, and LAN backup logic.
- `lib/screens/` and `lib/widgets/` contain the Flutter UI.
- `test/` contains unit and widget regression tests; `integration_test/` contains device-level flows.
- `android/` and `ios/` contain platform projects.
- `Tools/Build-Android.ps1` is the only Android release packaging entry point.
- `dist/android/` contains generated release artifacts and must not be committed.

## Product Constraints

- Maintain one unified app edition. Do not reintroduce standard/standalone flavors or multiple APK variants.
- Generate fixed speech assets with Edge TTS on the build machine and bundle them in the APK. The app runtime must never call Edge TTS or require internet access; dynamic text and missing assets fall back to Android system TTS in offline-only mode.
- The refund warning sound is generated locally and must remain consistent with the desktop warning behavior.
- Barcode scanning and uninterrupted recording are the core workflow. Avoid changes that require touch interaction during normal scanning work.
- Preserve local recordings and settings during upgrades. Never delete recordings based only on missing, stale, or partially matched metadata.
- Keep LAN backup and remote-recording cleanup semantics distinct from deleting local source recordings.

## Development Commands

Run commands from the repository root:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

Format only files changed for the current task:

```powershell
dart format <changed-files>
```

## Testing

- Add or update focused tests for every behavior change.
- Run the affected test file while iterating.
- Before committing, run `flutter analyze` and the relevant tests.
- Before a release, use `Tools/Build-Android.ps1`; it runs the full analysis and test suite before packaging.
- The release script must validate and reuse matching speech assets, generating only missing or changed fixed prompts before packaging.
- Recording, camera, audio, permissions, background lifecycle, installation upgrades, and LAN backup changes still require real-device validation when affected.

## Android Release

The release script generates one APK:

```powershell
pwsh -NoProfile -File Tools\Build-Android.ps1 `
  -VersionName <x.y.z> `
  -VersionCode <increasing-integer> `
  -SigningDirectory <external-signing-directory>
```

- Keep the default version in `Tools/Build-Android.ps1` synchronized with `pubspec.yaml`.
- Increase both `VersionName` and `VersionCode` for an installable upgrade.
- Keep keystores and `签名凭据.txt` outside the repository.
- Never print, commit, copy, or package signing credentials.
- Release output is `dist/android/PackingProof-Mobile.apk`, with `SHA256SUMS.txt` and `build-manifest.json`.
- Treat the build as successful only when bundled speech assets, metadata, Git revision, formal signature, and SHA256 validation all pass.

## Change Discipline

- Keep changes focused and preserve the existing Flutter/Dart style.
- Do not mix unrelated fixes, features, refactors, documentation, or release maintenance in one commit.
- Avoid broad formatting, generated-file churn, dependency upgrades, or platform changes unless required.
- Inspect `git status`, the relevant diff, and the staged diff before committing.
- Do not commit build outputs, local recordings, caches, logs, credentials, or machine-specific configuration.
