# PROP INTELLIGENCE repository audit — 2026-09-11

## Scope and safety

- Repository: `C:\Users\PI\Projects\PROP INTELLIGENCE\prop_intelligence`
- Starting branch: `main`
- Starting commit: `50be1559aa64f499ebd3769f8dc4bb0ebf0edfbc`
- Starting worktree: clean
- Audit branch: `codex/repository-wide-prop-audit`
- Audited code/fix commit: `63e73e9` (`fix prop startup and release state races`)
- Final tracked state at handoff: the code/fix commit plus this report-only
  documentation commit; worktree clean.
- No push, deployment, hosting-plan change, production migration, production
  write, cache flush, or provider-intensive load test was performed.
- No credential value was printed. Required provider/database secret names are
  present in local/CI/Render configuration, but live values were not disclosed
  or modified.

## Architecture and prop path

1. Provider adapters in `python_backend/providers/` fetch event and market data.
2. `python_backend/services/raw_ingestion_service.py` publishes raw envelopes;
   `python_backend/services/sync_service.py` controls seasonal coverage,
   bounded retries, provider quota lanes, and the global sync pipeline.
3. `python_backend/services/prop_processor.py::process_and_cache_props`
   validates and normalizes rows and protects a valid cache from invalid or
   incomplete event refreshes.
4. `python_backend/database/cache.py::PropCache` holds the local catalog.
5. `python_backend/services/distributed_cache_service.py` publishes the shared
   compressed catalog and manifest. `prop_catalog_snapshot_service.py` stores
   and loads the durable recovery snapshot.
6. `python_backend/main.py::_cached_prop_catalog_singleflight`,
   `_rebuild_prop_catalog_from_local`, `_refresh_prop_catalog_resilient`, and
   `/api/props` read, recover, filter, sort, paginate, and return the catalog.
7. `python_backend/routers/realtime.py::live_updates` sends catalog revision
   hints; realtime is not the only path to initial data.
8. `lib/services/api_service.dart::_fetchPropPage` authenticates and downloads
   bounded pages. `lib/services/prop_repository.dart` shares requests and keeps
   cache/account scope together. `prop_sync_coordinator.dart` reconciles
   revisions and lifecycle changes.
9. `lib/widgets/prop_grid.dart` races the last usable client snapshot against a
   live first page, rejects obsolete request keys, retries suspicious broad
   empty responses, orders rows, warms visible images, and renders cards.
10. `lib/widgets/main_dashboard.dart` owns sport, site, category, quick-filter,
    alert, and route state.

## Trustworthy baseline and verification

| Check | Result |
|---|---|
| `python -m pytest python_backend/tests -q` (before edits) | exit 0; 1,221 passed; 17.32 s |
| `flutter analyze` (before edits) | exit 0; no issues; 7.6 s |
| `flutter test` (before edits) | exit 0; 449 passed; about 61 s |
| `python tools/harden_release.py` | exit 0; Bandit, dependency audit, and debug-flag gates passed |
| safe configured `flutter build web --release` | exit 0; 66.3 s |
| focused post-fix Flutter regression run | exit 0; 30 passed |
| `flutter analyze` (post-fix) | exit 0; no issues; 5.2 s analyzer time |
| `python -m pytest python_backend/tests -q` (post-fix) | exit 0; 1,221 passed; 11.77 s |
| `flutter test` (post-fix) | exit 0; 453 passed; about 51 s |

The release web build used safe non-secret placeholder Supabase values and the
configured production API URL. It proves compilation, not authenticated
production behavior.

## Read-only production observations

Measured on this Windows audit host over the existing connection on 2026-09-11.
The host did not trust the certificate chain presented for the production
domains, so requests required certificate verification to be disabled for this
diagnostic only. The application was not changed and the browser interstitial
was not bypassed.

- `/health`, `/ready`, `/privacy`, `/terms`, and `/workspace/`: HTTP 200.
- `/api/props/readiness`: 20 sequential lightweight samples, all HTTP 200;
  median 0.318308 s, p95 0.552546 s, min 0.232691 s, max 0.552546 s, response
  size 264 bytes.
- Latest readiness payload: 6,976 catalog rows; source `shared-cache`;
  recovery `false`; data updated `2026-09-11T14:39:21.967775Z`; catalog
  published `2026-09-11T14:41:27.820608+00:00`; deployed version
  `50be1559aa64f499ebd3769f8dc4bb0ebf0edfbc`.
- `/api/operations/customer-journey-readiness`: status `ok`; inventory,
  player search, category filter, game times, player photos, and model-learning
  checks reported ready; response time reported as 461 ms.

These public endpoints do not measure authenticated login-to-first-card time,
initial board request count, or initial board payload size. Those checks remain
blocked on this host by the certificate trust problem and lack of a connected
authenticated staging browser session.

## Confirmed defects repaired

### P1 — account switch could unshare the new prop request

- Reproduction: begin a request, change account/access scope, begin the same
  query, then allow the old request to complete first.
- Root cause: the old request unconditionally removed the shared map entry by
  query key, even when that entry belonged to the new account generation.
- Fix: `PropRepository.load` now removes only the identical Future it owns.
- Test: `obsolete account completion cannot unshare the new account request`.

### P1 — authenticated backend status falsely reported offline

- Reproduction: call builder backend status against the production protected
  `/api/props` endpoint.
- Root cause: the health method authenticated `/health` implicitly because it
  is public, then requested protected props without an Authorization header.
- Fix: send authenticated headers, retry once after token refresh on 401, and
  request only one row without reliability details.
- Test: `backend_health_auth_test.dart` guards the protected probe behavior.

### P2 — cleared alert badge could reappear

- Reproduction: start an inbox request, open the alert page (which clears the
  badge), then allow the older unread response to finish.
- Root cause: concurrent alert loads had no generation/ownership guard.
- Fix: invalidate older alert loads when the inbox opens and ignore obsolete
  completions.
- Test: alert inbox regression verifies both invalidation and response guard.

### P2 — production native app exposed an SDK sample prompt

- Reproduction: successful native OneSignal registration.
- Root cause: release startup displayed the OneSignal integration sample dialog
  and coupled it to a notification permission request.
- Fix: remove the SDK sample confirmation path. Permission remains controlled
  by the product's intended notification UX.
- Test: Apple configuration regression rejects the sample dialog in source.

### P1 — local CI verifier could continue after native failures

- Root cause: PowerShell did not explicitly convert every native non-zero exit
  code into a terminating failure.
- Fix: all Flutter/Python native commands now run through a checked wrapper.
- Test: `PI_VERIFY_CI_SELF_TEST=1` runs a child command that exits 17; the
  verifier exits 1 as required.

## Existing protections inspected and retained

- Category facets remain separated by sport/site, use total unfiltered facets
  after a category is selected, stay expanded, and expose visible horizontal
  scrollbars on compact layouts.
- Scoreboard parsing rejects ESPN logo URLs from the wrong league and falls
  back to initials; backend normalization replaces wrong provider logos with
  the league-specific ESPN catalog when possible. Existing Python and Flutter
  tests cover NFL/MLB cross-league cases.
- Initial props do not depend exclusively on realtime; the board requests a
  bounded first page and can show its last successful client snapshot first.
- Backend catalog rebuild/publish paths use single-flight/manifest behavior and
  retain durable recovery data rather than replacing a valid catalog with an
  unsuccessful empty refresh.
- Flutter request keys include filters and access scope, and stale filter
  responses are rejected.

## Coverage checklist

| Area | Inspected | Tested | Changed | Status |
|---|---:|---:|---:|---|
| Flutter startup/auth/App Store paths | yes | yes | yes | local checks pass |
| Prop API client/repository/coordinator | yes | yes | yes | local checks pass |
| Board filters/categories/card loading | yes | yes | no | existing protections pass |
| Alert inbox/header state | yes | yes | yes | race repaired |
| Player image resolution/widgets | yes | yes | no | existing tests pass |
| Scoreboard service/controller/logos | yes | yes | no | existing tests pass |
| Backend prop endpoint/catalog recovery | yes | yes | no | public readiness healthy |
| Provider ingestion/normalization | yes | yes | no | mocked/local tests pass |
| Redis publication/durable snapshot | yes | yes | no | live metrics unavailable |
| Slips/grading/builder/research/chat/admin | route and tests reviewed | yes | no | smoke/unit coverage passes |
| iOS/Android/web/CI/Render config | yes | build/static tests | CI verifier only | no device archive built |
| Live database indexes/query plans | partial | blocked | no | credentials/tooling unavailable |
| Live Render logs/CPU/RAM/Redis peak memory | no | blocked | no | no authenticated Render CLI/MCP session |
| Clean physical iPad/iPhone journeys | no | blocked | no | requires devices/TestFlight |

## Remaining risks and blocked investigations

- The exact Apple-review missing-props sequence was not reproducible from this
  Windows host because authenticated production browser access is blocked by
  its certificate trust store. The confirmed repository account-switch race is
  consistent with intermittent first-load behavior, but it is not claimed as
  the only possible production cause.
- Live Render API/worker logs, Redis peak memory, database pool saturation, and
  worker overlap could not be read. A connected read-only Render session is
  needed to compare request IDs and catalog versions during a failure.
- No valid before/after login-to-first-card timing can be claimed until the same
  authenticated account, device, build, network, and dataset are measured.
- Physical iOS/iPadOS cold-install, Apple login, sandbox purchase discovery,
  background/resume, and TestFlight checks remain device work.
- Dependency updates were deliberately not made; the audit found no evidence
  justifying a blanket upgrade.

## Proposed deployment and rollback plan (not executed)

1. Review this branch diff and run CI from the audit branch.
2. Deploy backend/web to staging with the same environment-variable names and
   confirm no secret is compiled into the client.
3. Run authenticated cold/warm journeys on desktop, iPhone, and clean iPad;
   record first-card timing, request count/size, filter switching, alert badge,
   scoreboard logos, background/resume, account switch, and logout/login.
4. Correlate API/worker logs by request/catalog version and observe database,
   Redis, API, and worker peak memory across at least two refresh cycles.
5. Promote one reviewed commit. Keep the previous deployment artifact and
   database schema unchanged so rollback is application-only.
6. Roll back immediately if readiness becomes non-200, catalog unexpectedly
   reaches zero, stale age breaches policy, authenticated first-card loading
   regresses, or error rate rises. Do not erase the last good snapshot.
