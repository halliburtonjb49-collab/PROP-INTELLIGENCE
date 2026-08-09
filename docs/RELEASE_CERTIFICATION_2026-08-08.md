# Release Certification - 2026-08-08

## Scope

This certificate covers the provider reliability, three-day coverage, Props board simplification, guided onboarding, product observability, and targeted architecture work based on baseline commit `c5e4e9f`.

## Product acceptance criteria

- Provider coverage is calculated from the full three-day catalog, not only the active filter.
- Every expected provider is classified as live, stale, missing, or unknown.
- The board shows freshness, future event count, provider coverage, and recovery status.
- Partial or stale coverage requests the existing deduplicated background refresh; it never invents or substitutes lines from another provider.
- Compact layouts replace the duplicate provider carousel with one site selector.
- Verdicts expose counts, accessible labels, and a contextual decision guide.
- Onboarding explains site/market selection, verdict meanings, reliability, evidence, and slip tracking.
- Production telemetry records aggregate product actions, slow loads, and safe error fingerprints without raw exception text or user details.
- Synthetic product telemetry is excluded from prop sentiment rollups.

## Automated certification

| Gate | Result | Evidence |
| --- | --- | --- |
| Backend tests | PASS | 853 tests passed |
| Flutter tests | PASS | 213 tests passed |
| Flutter static analysis | PASS | No issues found |
| Production web build | PASS | `flutter build web --release` |
| Windows release build | PASS | `build/windows/x64/runner/Release/prop_intelligence.exe` |
| Diff integrity | PASS | `git diff --check` |
| Phone-width reliability UI | PASS | 360 x 800 widget coverage, included in Flutter suite |
| Android release build | PENDING HOSTED CI | Local Android SDK/AVD is unavailable |
| Production smoke test | PENDING DEPLOYMENT | Must be performed against the deployed commit |

The Windows build required a target-scoped compatibility acknowledgement because `flutter_inappwebview_windows` still includes Microsoft's deprecated experimental coroutine header. The release executable builds successfully after the narrowly scoped CMake fix. Remaining compiler output is third-party warning-level output, not a failed gate.

## Available test targets

- Windows 10 desktop: available and release-build certified.
- Chrome 151 web: available; production web bundle certified.
- Edge 151 web: available; production web bundle certified.
- Android physical device/emulator: not available in this environment.
- iOS physical device/simulator: not available on this Windows host.

## Manual real-device matrix

These checks remain required before declaring the product a literal 10/10 release across every supported device.

| Device | Orientation | Required checks | Status |
| --- | --- | --- | --- |
| Current Android phone | Portrait and landscape | Sign-in, onboarding, site/sport/category selection, reliability details, verdict guide, prop selection, slip lock, billing return | NOT EXECUTED |
| Current iPhone | Portrait and landscape | Same workflow plus safe-area and keyboard behavior | NOT EXECUTED |
| Android tablet | Portrait and landscape | Rail wrapping, drawers, details sheet, slip workflow | NOT EXECUTED |
| iPad | Portrait and landscape | Rail wrapping, drawers, details sheet, slip workflow | NOT EXECUTED |
| Windows desktop | Resizable | Startup, navigation, reliability details, embedded browser paths | BUILD PASS; INTERACTIVE PASS PENDING |
| Chrome and Edge | 360, 768, 1440 widths | Onboarding, filter density, reliability sheet, empty/error/recovery states | AUTOMATED PASS; PRODUCTION SMOKE PENDING |

## Production smoke checklist

After deployment:

1. Confirm `/ready` reports the deployed commit.
2. Sign in and verify the reliability strip appears above the sport/category rails.
3. Open reliability details and verify three future dates plus provider statuses.
4. Select PrizePicks and confirm a partial-feed warning appears only when its catalog is genuinely incomplete.
5. Confirm mobile shows one prop-site selector rather than duplicated provider buttons.
6. Open the verdict `?` guide and verify all verdict explanations.
7. Trigger a normal filter interaction and confirm the admin observability endpoint aggregates product events.
8. Confirm a stale or partial feed queues one deduplicated recovery job.
9. Confirm no provider's missing lines are replaced with another provider's lines.
10. Run the primary prop-builder and billing-return workflows.

## Release decision

The change set is certified for automated backend, Flutter, web-release, and Windows-release gates. Final cross-platform certification remains conditional on hosted Android CI, production smoke testing, and physical Android/iOS execution. Those limitations are recorded explicitly rather than being treated as passed.