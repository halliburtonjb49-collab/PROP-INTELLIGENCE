# PI Sync Manager — Stage B implementation results

Prepared September 6, 2026.

## Scope and source baseline

- Development worktree: `C:\Users\PI\Projects\PROP INTELLIGENCE\prop_intelligence_pi_sync`
- Branch: `feat/pi-sync-manager`
- Actual base commit: `1d796eb40c56baec9979e348360c3cb7d3386eeb`
- Stage B was implemented on top of the uncommitted, reviewed Stage A workspace.
- The original project worktree was not edited.
- No commit, push, merge, deployment, Render setting, production credential, production API, Redis instance, or production database was used or changed.

Stage B adds a default-off authenticated revision-hint transport. It does not replace HTTP page fetching with full-catalog WebSocket delivery.

## Active path and contracts implemented

- The existing catalog assembly path remains the publisher. When the backend flag is enabled, it streams a complete compressed catalog into a temporary Redis key, computes its digest/count, and promotes the snapshot and revision manifest in one Lua operation.
- Redis allocates monotonic publication sequences. A publisher that finishes late cannot replace a newer accepted catalog. When a local worker loses that race, its process-local cache is replaced with the accepted shared snapshot instead of labeling older rows with the newer revision.
- The manifest includes an epoch, sequence, content revision, content digest, snapshot key, row count, source-updated time, and publication time. Cache reads do not advance source freshness.
- `/api/props` retains its protected `private, no-store` behavior and existing authenticated/scoped response caching. Its ETag and `X-PI-Content-Revision` are built from the exact in-memory snapshot/version pair served. CORS exposes the ETag, revision, and app-version headers.
- The existing `/api/realtime/ws` route negotiates protocol v2 only when `PI_PROP_REVISION_FEED_ENABLED=true`. V2 emits a small `props.revision` manifest hint and never scans/serializes the full catalog in its polling loop.
- Prop subscriptions now require the same valid Core-or-higher membership used by `/api/props`, including when the performance flag is off. Tokens are sent in the authentication message, not the URL.
- Protocol v1 remains explicitly compatible for authenticated old clients and continues to receive `props.updated` rows. Protocol v2 clients reconcile through the existing authenticated HTTP path.
- A current manifest is included in the v2 connection-ready event, so reconnects and subscriptions reconcile even if no new event occurs. The Stage A low-rate HTTP reconciliation remains the missed-hint fallback.
- Broadcast sends are concurrent and bounded by a per-client timeout. A slow/dead socket is removed without delaying healthy clients. Realtime errors expose only a sanitized message.
- The Stage A `PropSyncCoordinator` opens the v2 connection only when the new Flutter flag is enabled, ignores duplicate/out-of-order sequence hints for the same epoch, coalesces accepted hints, and preserves cached rows while the scoped HTTP request refreshes.

## Changed files

Stage B-specific changes:

- `python_backend/services/distributed_cache_service.py`
  - Atomic compressed snapshot/manifest promotion, sequence allocation, digesting, and stale-writer rejection.
- `python_backend/main.py`
  - Default-off manifest publication path, accepted-snapshot recovery after a worker race, revision-scoped HTTP metadata, and exposed response headers.
- `python_backend/routers/realtime.py`
  - Core entitlement authentication for props, v2 negotiation, initial/current manifest, minimal hints, bounded concurrent sends, sanitized errors, and authenticated v1 compatibility.
- `lib/config/pi_sync_flags.dart`
  - Adds compile-time `PI_PROP_REVISION_FEED_ENABLED`, default `false`.
- `lib/models/prop_page.dart`
  - Carries the HTTP content revision with the immutable page result.
- `lib/services/api_service.dart`
  - Reads `X-PI-Content-Revision` from the exact page response.
- `lib/services/live_update_service.dart`
  - Requests a negotiated protocol version while reusing the existing token-message authentication and reconnect lifecycle.
- `lib/services/prop_sync_coordinator.dart`
  - Default-off v2 subscription, sequence/epoch guards, coalesced HTTP reconciliation, and existing foreground/resume fallback.
- `python_backend/tests/test_distributed_cache_service.py`
  - Covers consistent manifest/snapshot promotion and rejection of an older late publisher.
- `python_backend/tests/test_realtime_api.py`
  - Covers prop auth, Core entitlement parity, v1 compatibility, v2 initial manifest, metadata-only hint payload, and slow-client isolation.
- `test/pi_sync_flags_test.dart`
  - Proves both revision-transport flag states and the default-off contract.

Stage A files remain part of the same uncommitted workspace and are documented in `IMPLEMENTATION_RESULTS_STAGE_A.md`.

Flutter tooling reports generated Linux/macOS/Windows plugin registrant files as modified because of local line-ending normalization. They have no textual diff and contain no Stage B implementation.

## Tests actually executed

All checks used local mocks/test doubles. No production credentials or production service calls were used.

1. Focused backend Stage B tests:

   ```powershell
   python -m pytest python_backend/tests/test_distributed_cache_service.py python_backend/tests/test_realtime_api.py -q --basetemp .pytest-stage-b-focused
   ```

   Result: **17 passed, 0 failed**.

2. Full backend suite after the final entitlement and race changes:

   ```powershell
   python -m pytest python_backend/tests -q --basetemp .pytest-stage-b-final
   ```

   Result: **1182 passed, 0 failed**.

   An earlier full run also completed every test but Python 3.14/pytest raised a Windows permission error while removing its global `pytest-current` temporary link after execution. Re-running with a workspace-local `--basetemp` completed cleanly and produced the result above.

3. Focused Flutter sync/board/ticket tests:

   ```powershell
   flutter test test/pi_sync_flags_test.dart test/prop_repository_test.dart test/prop_grid_test.dart test/slip_line_reconciliation_test.dart
   ```

   Result: **11 passed, 0 failed**.

4. Full Flutter suite:

   ```powershell
   flutter test
   ```

   Result: **409 passed, 0 failed**.

5. Static analysis:

   ```powershell
   flutter analyze
   ```

   Result: **No issues found**.

6. Enabled Stage A + Stage B release web compilation:

   ```powershell
   flutter build web --release --dart-define=PI_SYNC_MANAGER_ENABLED=true --dart-define=PI_PROP_REVISION_FEED_ENABLED=true
   ```

   Result: **passed**; `build\web` was produced locally and was not published.

## Feature flags and settings

- Flutter repository/coordinator: `PI_SYNC_MANAGER_ENABLED`; compile-time boolean; default `false`.
- Flutter revision transport: `PI_PROP_REVISION_FEED_ENABLED`; compile-time boolean; default `false`.
- Backend revision publication/transport: `PI_PROP_REVISION_FEED_ENABLED`; environment boolean; default `false`.

No setting was changed. Both Flutter flags require a new build to change. The backend flag must not be enabled before compatible backend support is reviewed and deployed.

## Local preview instructions

Use only the project's existing non-production configuration.

Legacy/default transport:

```powershell
flutter run -d chrome
```

Stage A repository with low-rate HTTP reconciliation, but no revision socket:

```powershell
flutter run -d chrome --dart-define=PI_SYNC_MANAGER_ENABLED=true
```

Stage A + Stage B client transport against a compatible local mocked/backend environment:

```powershell
flutter run -d chrome --dart-define=PI_SYNC_MANAGER_ENABLED=true --dart-define=PI_PROP_REVISION_FEED_ENABLED=true
```

For the local backend, set `PI_PROP_REVISION_FEED_ENABLED=true` only in that non-production process. Exercise sign-in, entitlement changes, reconnect, background/resume, rapid filter changes, scroll position, open research, and ticket selections. Confirm the socket sends only manifest hints and the rows arrive through authenticated `/api/props`.

## Rollback

The immediate client rollback is a build with both flags absent or false:

```powershell
flutter build web --release --dart-define=PI_SYNC_MANAGER_ENABLED=false --dart-define=PI_PROP_REVISION_FEED_ENABLED=false
```

The backend rollback is `PI_PROP_REVISION_FEED_ENABLED=false`, which retains authenticated v1 compatibility and the legacy catalog publisher. Do not flush Redis: existing revision keys expire and are harmless to the old path. Keep the props-subscription authentication fix. If source rollback is later required, use a reviewed revert/known-good commit; do not force-push, hard-reset, drop schema, or clear production caches.

## Unfinished and rollout-gated items

1. Review the Stage A + B diff before any commit or deployment.
2. Run a non-production integration test with a real disposable Redis instance and two API/worker processes to measure publication ordering and reconnect behavior across processes. Unit tests use an in-memory Redis test double.
3. Capture release/profile measurements for provider-to-publication, publication-to-screen, response bytes, API latency, and cached first paint. No production speed improvement is claimed by this implementation report.
4. Run the repository's complete CI matrix and manual phone/tablet/desktop visual checks before rollout.
5. Deploy compatible backend support before building/enabling the client transport, then canary the default-off flags. Record known-good frontend/backend versions first.
6. Stage C owner health/telemetry is not implemented. Proceed only after Stage B review.
7. No commit, push, merge, deployment, Render modification, or production validation has been performed.
