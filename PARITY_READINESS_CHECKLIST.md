# Swift Sample Parity Readiness Checklist

This checklist defines whether `public-swift-sdk-sample-repo` is ready to validate Swift SDK behavior against RN gold-standard behavior.

## Current Status

- Tarball wiring to sample app: PASS
- Vendor extraction integrity: PASS
- Manual iOS behavior validation surface: PASS
- Deterministic parity gate (RN vs Swift mirrored comparator): PARTIAL

## 1) SDK Bundle Integrity (Must Pass)

- [x] `vendor/TruflagSDK.tar.gz` exists.
- [x] `vendor/TruflagSDK.tar.gz.sha256` matches the archive.
- [x] `scripts/bootstrap-sdk.ps1` / `bootstrap-sdk.sh` verify hash before extraction.
- [x] `project.yml` points package dependency to `vendor/TruflagSDK`.
- [x] Extracted `vendor/TruflagSDK` is byte-identical to `sdk/native/ios/TruflagSDK` for source and tests.

Verification commands:

```powershell
./scripts/bootstrap-sdk.ps1
xcodegen generate
```

```bash
./scripts/bootstrap-sdk.sh
xcodegen generate
```

## 2) Manual Runtime Validation Coverage (Sample App)

The sample UI currently supports validation of:

- [x] Configure + startup readiness.
- [x] Identity lifecycle (`login`, `setAttributes`, `logout`).
- [x] Manual refresh and read paths.
- [x] Stream/poll state visibility (`streamStatus`, `pollingActive`, event timestamps).
- [x] Track API invocation from UI.
- [x] Exposure API invocation from UI.
- [x] Live filtered SDK logs and copy-to-clipboard flow for triage.

This makes the app strong for interactive iOS behavior checks and regressions.

## 3) Deterministic Parity Gate Coverage (RN-Equivalent Strict Gate)

To be fully parity-gate complete, this sample repo still needs these capabilities in an automated comparator layer:

- [ ] Mirrored RN-vs-Swift scenario execution with shared scripted transport fixtures.
- [ ] Controlled clock and storage seeding for deterministic startup/TTL/retry timing.
- [ ] Normalized output comparator (`state`, network requests, track payloads, stream lifecycle transitions, errors).
- [ ] Strict pass/fail report artifact per scenario with divergence metadata.

Note:
- Existing `TruflagSwiftSampleTests` is a live smoke test and is useful evidence.
- Live smoke is not sufficient as a strict deterministic parity gate by itself.

## 4) Recommended Validation Sequence

1. Run bundle/bootstrap integrity.
2. Run simulator build/tests in this sample repo.
3. Execute manual app checklist flows on device/simulator and capture logs.
4. Run deterministic parity suite from monorepo parity tooling (if required as release gate).
5. Record PASS/FAIL per parity scenario and close any remaining gaps.

## 5) CI Baseline (Already Present)

- [x] Bootstrap bundled SDK.
- [x] Generate project via XcodeGen.
- [x] Build app on simulator.
- [x] Run test target on simulator.

CI file: `.github/workflows/ios-sample-ci.yml`
