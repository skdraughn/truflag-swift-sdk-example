# Truflag Swift SDK Public Sample

Standalone iOS sample app that bundles the Truflag Swift SDK as a tarball for reproducible builds.

## What is bundled

- `vendor/TruflagSDK.tar.gz`: packaged Swift SDK source
- `vendor/TruflagSDK.tar.gz.sha256`: checksum for integrity verification

The app consumes the SDK from `vendor/TruflagSDK` after extraction.

## Quickstart

### Windows (PowerShell)

```powershell
./scripts/bootstrap-sdk.ps1
xcodegen generate
# then build/test on macOS or CI
```

### macOS/Linux

```bash
chmod +x ./scripts/bootstrap-sdk.sh
./scripts/bootstrap-sdk.sh
xcodegen generate
xcodebuild -project TruflagSwiftSample.xcodeproj -scheme TruflagSwiftSample -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TruflagSwiftSample.xcodeproj -scheme TruflagSwiftSample -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

## CI

GitHub Actions (`.github/workflows/ios-sample-ci.yml`) performs:

1. SDK tarball integrity verification + extraction
2. Xcode project generation
3. iOS simulator build + tests

GitHub Actions (`.github/workflows/ios-unsigned-ipa.yml`) can produce an unsigned device `.ipa` artifact for sideload workflows.

## Build an IPA from GitHub Actions (Windows-friendly)

1. Open the repo on GitHub.
2. Go to **Actions** -> **ios-unsigned-ipa**.
3. Click **Run workflow**.
4. Wait for job completion, then open the run and download artifact `TruflagSwiftSample-unsigned-ipa`.
5. Use Sideloadly/AltStore on Windows to sign and install that `.ipa` with your Apple ID.

Notes:
- The artifact is intentionally unsigned in CI.
- CI does not require Apple signing certificates for this path.

## Updating the bundled SDK tarball

From your private monorepo root:

```powershell
tar -czf public-swift-sdk-sample-repo/vendor/TruflagSDK.tar.gz --exclude='.build' -C sdk/native/ios TruflagSDK
$hash = Get-FileHash public-swift-sdk-sample-repo/vendor/TruflagSDK.tar.gz -Algorithm SHA256
"$($hash.Hash)  TruflagSDK.tar.gz" | Set-Content public-swift-sdk-sample-repo/vendor/TruflagSDK.tar.gz.sha256
```

Then commit both files together.
