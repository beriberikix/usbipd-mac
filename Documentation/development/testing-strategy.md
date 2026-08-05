# Testing Strategy

## What actually runs

```bash
swift test --parallel
```

That is the whole test suite. `Package.swift` declares exactly two test targets:

| Target | Path |
| --- | --- |
| `USBIPDCoreTests` | `Tests/USBIPDCoreTests` |
| `USBIPDCLITests` | `Tests/USBIPDCLITests` |

Both also compile `Tests/SharedUtilities` via their `sources:` list.

`swift test` requires XCTest, which ships with Xcode. A machine with only the Command
Line Tools cannot run it — `error: no such module 'XCTest'`. CI runs on `macos-latest`,
which has full Xcode, and is currently the only place the suite executes.

## What does not run, and why

This document previously described a three-tier development / CI / production testing
system with per-tier timing budgets, driven by
`Scripts/run-{development,ci,production}-tests.sh`. That system never executed a single
test.

Each script ran `swift test --filter <Tier>` against tier names — `DevelopmentTests`,
`CITests`, `ProductionTests` — that were never declared as targets in `Package.swift`.
SwiftPM's `--filter` is a regex matched against `Target.Class/method`, so the filters
matched nothing, `swift test` exited 0, and the job reported success. The reported test
count was hardcoded (`"~50"` for CI), so the summary looked plausible. This stood from
August 2025 until August 2026.

The scripts and the CI step that called them were removed in August 2026.

## Test code that is not compiled

Several directories under `Tests/` are referenced by no target and therefore never
build. They are retained pending triage, not deleted, but nothing in them is exercised:

- `Tests/CITests.swift` (a loose file at the `Tests/` root) and `Tests/CITests/`
- `Tests/IntegrationTests/`, `Tests/SystemExtensionTests/`, `Tests/QEMUIntegrationTests/`
  — declared in `Package.swift` but commented out as "temporarily disabled for CI stability"
- `Tests/Integration/`, `Tests/ProductionTests/`, `Tests/PerformanceTests/`,
  `Tests/Distribution/`, `Tests/ReleaseValidation/`, `Tests/ReleaseWorkflowTests/`,
  `Tests/TestMocks/` — referenced by nothing at all

Do not cite coverage from these. If you revive one, add it as a real `testTarget` and
confirm it compiles against current APIs first.

## Guard against regression

`.github/actions/run-test-suite` counts the tests that actually executed by parsing
`swift test` output and **fails the job if the count is zero**, even when `swift test`
exits 0. That guard is what would have caught the filter bug on the day it was
introduced. Do not remove it, and do not replace a real count with an estimate.

## Hardware-dependent validation

`./Scripts/validate-usb-entitlements.sh` measures what userspace can do with attached
USB devices under different code-signing entitlements. It is not part of `swift test`.
Its `--self-test` mode runs in CI and validates the harness itself; the per-device
measurement needs real hardware on a real Mac. See
[entitlement-validation.md](entitlement-validation.md).
