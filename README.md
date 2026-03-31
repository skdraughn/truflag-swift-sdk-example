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

## Updating the bundled SDK tarball

From your private monorepo root:

```powershell
tar -czf public-swift-sdk-sample-repo/vendor/TruflagSDK.tar.gz --exclude='.build' -C sdk/native/ios TruflagSDK
$hash = Get-FileHash public-swift-sdk-sample-repo/vendor/TruflagSDK.tar.gz -Algorithm SHA256
"$($hash.Hash)  TruflagSDK.tar.gz" | Set-Content public-swift-sdk-sample-repo/vendor/TruflagSDK.tar.gz.sha256
```

Then commit both files together.
