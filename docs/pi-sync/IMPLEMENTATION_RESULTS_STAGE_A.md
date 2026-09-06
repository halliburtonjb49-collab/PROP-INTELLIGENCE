# PI Sync Manager — Stage A implementation results

Prepared September 6, 2026.

## Scope and source baseline

- Development worktree: `C:\Users\PI\Projects\PROP INTELLIGENCE\prop_intelligence_pi_sync`
- Branch: `feat/pi-sync-manager`
- Actual base commit: `1d796eb40c56baec9979e348360c3cb7d3386eeb`
- The original project worktree was not edited.
- No commit, push, merge, workflow, deployment, Render setting, production credential, production API, or production database was used or changed.

Stage A is implemented as a default-off Flutter client path. Stage B/C transport and backend publication work is intentionally not included.

## Active routes and consumers integrated

- `MainDashboard` now owns one session-scoped `PropRepository` and `PropSyncCoordinator` when the feature flag is enabled.
- The active `PropGrid` subscribes to the exact current query and uses the coordinator for initial load, refresh, polling, lifecycle pause/resume, and load-more requests.
- `MainDashboard` consumes the typed `PropPage`, so rows, counts, facets, provider coverage/reliability, provenance, and recovery state are applied from the same response.
- Active ticket/current-market reconciliation consumes the shared rows. It preserves `original_line`/`line` and writes a separate `current_line` comparison.
- Existing legacy `fetchProps` callers remain on the old adapter unless migrated. The old path remains the default and keeps its existing refresh behavior.

No separate watchlist screen was forced into an all-sports catalog request. The active ticket consumer was the equivalent current-market consumer found on this route.

## Changed files and contracts

- `lib/models/prop_page.dart`
  - Adds immutable `PropQuery`, `PropPage`, and measured `PropPageStatus` contracts.
  - Query identity includes every response-shaping filter, sort, page offset/limit, reliability option, schema version, and account/entitlement access scope.
  - Rows and all mutable metadata collections are frozen together.
- `lib/config/pi_sync_flags.dart`
  - Adds compile-time `PI_SYNC_MANAGER_ENABLED`; default is `false`.
  - Provides a test-only override used to exercise both paths without changing the production default.
- `lib/services/api_service.dart`
  - Adds typed `fetchPropPage` on the existing authenticated HTTP, parsing, fallback, and request-sharing path.
  - Keeps `fetchProps` as a compatibility adapter.
  - In-flight keys and v6 persistent cache keys include access scope.
  - Typed fallback pages keep their own rows and metadata.
  - Protected v6 caches can be invalidated without deleting unrelated preferences. Legacy unscoped v5 startup data is accepted only while signed out and cannot cross into an authenticated account.
- `lib/services/prop_repository.dart`
  - Adds bounded immutable page caching (12 entries by default), identical-request deduplication, subscription reference counts, preserved-page refresh state, and generation/scope guards that reject late old-session responses.
- `lib/services/prop_sync_coordinator.dart`
  - Adds coalesced invalidation, one shared low-rate HTTP reconciliation timer, foreground pause, one resume reconciliation, and account/entitlement scope invalidation.
- `lib/services/auth_manager.dart`
  - Invalidates protected prop caches on sign-out.
- `lib/services/slip_manager.dart`
  - Allows the shared rows to update current-market comparisons while preserving the ticket's recorded original line.
- `lib/widgets/main_dashboard.dart`
  - Owns/injects the coordinator for the authenticated dashboard session and updates its scope when user/tier/role changes.
  - Applies typed page metadata atomically rather than reading global last-response values on the new path.
- `lib/widgets/prop_grid.dart`
  - Connects the active board to repository subscriptions behind the flag.
  - Prevents old query responses from applying after filters change.
  - Preserves the existing card order for unchanged identities, cached board during refresh, widget/card keys, selected tickets, research widget state, filters, and surrounding scroll position.
  - Removes duplicate per-widget polling and duplicate resume refresh only on the new path.
  - Adds existing-theme status labels: Checking, Updating, Provider delayed, Reconnecting, Offline — showing saved data, and Auto-updating.
  - The old path is unchanged when the flag is off.
- `test/prop_repository_test.dart`
  - Covers exact query identity, immutable atomic metadata, in-flight deduplication, cache bounds, old account-response rejection, filter metadata isolation, no blank refresh, lifecycle pause/resume, reconciliation, and reference release.
- `test/pi_sync_flags_test.dart`
  - Proves default-off and explicit old/new flag states.
- `test/slip_line_reconciliation_test.dart`
  - Proves live refresh cannot overwrite a saved ticket's original line.
- `test/prop_grid_test.dart`
  - Retains the old-path failure test and adds a mocked enabled-path integration test.

Flutter tooling marked generated Linux/macOS/Windows plugin registrant files as modified because of local line-ending normalization. They have no textual diff and contain no Stage A implementation.

## Tests actually executed

All tests were local/mocked. No production credentials were loaded and no production service calls were made.

1. Focused Stage A plus board/ticket regressions:

   ```powershell
   flutter test test/prop_grid_test.dart test/prop_repository_test.dart test/pi_sync_flags_test.dart test/slip_line_reconciliation_test.dart test/board_cache_test.dart test/board_filter_memory_test.dart test/grouped_card_selection_test.dart test/active_slip_controller_test.dart
   ```

   Result: **36 passed, 0 failed**.

2. Full Flutter suite after fixing scoped-cache legacy compatibility:

   ```powershell
   flutter test --concurrency=1
   ```

   Result: **408 passed, 0 failed**.

3. The lifecycle/reference-count test was added after that full run and executed directly:

   ```powershell
   flutter test test/prop_repository_test.dart
   ```

   Result: **7 passed, 0 failed**.

4. Static analysis after all implementation and test changes:

   ```powershell
   flutter analyze
   ```

   Result: **No issues found**.

5. Compile-only release web build with the Stage A path enabled:

   ```powershell
   flutter build web --release --dart-define=PI_SYNC_MANAGER_ENABLED=true
   ```

   Result: **passed**; `build\web` was produced locally. It was not published or deployed.

The first broad-suite attempt found three legacy v5 signed-out startup-cache regression failures. The implementation was corrected so legacy unscoped cache migration works only before authentication; the affected test file then passed 10/10 and the subsequent full suite passed 408/408.

## Not run or not proven

- Python/backend tests were not run because Stage A made no Python/backend changes and the requested vertical slice is the Flutter client repository/coordinator. Stage B backend transport/authentication remains separate.
- No production, staging, or live authenticated preview was run.
- No release/profile performance measurements were captured, so this document does not claim a measured login, API p95, payload, memory, or publication-to-screen improvement.
- A device-specific cold-start/cached-first-paint benchmark and manual phone/tablet/desktop visual pass remain rollout checks.
- Stage B WebSocket invalidation, shared revision manifests, Redis publication, and server-side diagnostics are not implemented.

## Feature flag and required settings

- Flag: `PI_SYNC_MANAGER_ENABLED`
- Type: Flutter compile-time `bool.fromEnvironment`
- Default: `false`
- No new package, database migration, credential, Render setting, or backend environment variable is required for Stage A.
- Because this is a compile-time Flutter flag, changing it requires a new local/test build.

## Local preview instructions

Use the project's existing non-production configuration. Do not substitute production credentials into a local command.

Old path (default):

```powershell
flutter run -d chrome
```

New Stage A path:

```powershell
flutter run -d chrome --dart-define=PI_SYNC_MANAGER_ENABLED=true
```

For a compilation-only web check with the same safe local configuration:

```powershell
flutter build web --release --dart-define=PI_SYNC_MANAGER_ENABLED=true
```

Compare the same saved session and filter sequence with the flag off/on. Verify cached first paint, rapid sport/site/filter switching, scroll position, an open research card, selected ticket legs, current-line comparison, background/resume, and sign-out/account switch. Do not publish the local build.

## Rollback

The immediate rollback is to build with the flag absent or explicitly false:

```powershell
flutter build web --release --dart-define=PI_SYNC_MANAGER_ENABLED=false
```

That selects the existing `fetchProps` and widget-refresh path; no cache flush or database action is needed. Keep authentication and scoped-cache invalidation changes. If source rollback is later required, use a reviewed revert/known-good commit for the files listed above; do not use a force push, `git reset --hard`, Redis flush, or schema drop.

## Unfinished rollout items

1. Review this diff and the feature-flag behavior locally with representative phone, tablet, and desktop sizes.
2. Capture baseline and enabled-path release/profile metrics using the acceptance document's definitions.
3. Run the repository's complete CI/build matrix before any authorized merge.
4. Implement and review Stage B separately before claiming real-time publication improvements.
5. Obtain explicit authorization before any commit, push, merge, deployment, infrastructure setting, or production validation.
