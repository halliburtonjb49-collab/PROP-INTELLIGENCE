# PI application audit status

Last updated: 2026-09-11  
Branch: `codex/repository-wide-prop-audit`  
Starting commit: `50be1559aa64f499ebd3769f8dc4bb0ebf0edfbc`  
Current audit commits: `63e73e9`, `12048c4`

This is a continuation ledger, not a claim that the application is bug-free or
production-verified. Detailed evidence is in
`docs/repository_audit_2026-09-11.md`.

## Current priority

Obtain an authenticated, read-only reproduction of the intermittent first-prop
load on a production-equivalent iPhone/iPad or staging browser. Correlate the
client request with API, worker, database, and Redis telemetry. The local audit
confirmed and fixed an account-scope request race, but live evidence is still
required to prove whether another production-stage failure remains.

## Coverage matrix

Status values: **not reviewed**, **inspected**, **tested**, **fixed**, or
**blocked**. `tested` means executable coverage ran; inventory alone is only
`inspected`.

| Area | Key implementation | Status | Evidence / next task |
|---|---|---|---|
| Repository/CI safety | `.github/workflows/*`, `tools/verify_ci_local.ps1` | fixed | Native failures now terminate verification; self-test exit 17 makes verifier exit 1. |
| Flutter entry/startup | `lib/main.dart`, auth initialization, app shell | fixed | Removed release OneSignal sample prompt; analyzer/build/tests pass. Physical cold-install remains blocked. |
| Authentication/session roles | `auth_manager.dart`, `supabase_service.dart`, API auth headers | tested | Role/tier and Apple configuration tests pass. Clean-device Apple/reviewer login blocked on physical devices. |
| Prop HTTP client | `lib/services/api_service.dart::_fetchPropPage` | fixed | Protected health probe now authenticates and refreshes a 401 token. Bounded first-page behavior inspected. |
| Prop repository/cache scope | `lib/services/prop_repository.dart` | fixed | Old-account completion can no longer remove the new account's shared request; regression passes. |
| Client sync/realtime | `prop_sync_coordinator.dart`, `live_update_service.dart` | tested | Reconcile/resume tests pass. Protocol v2 receives current manifest on `connection.ready`; HTTP remains source of rows. |
| Prop board rendering | `lib/widgets/prop_grid.dart` | tested | Cache/live race, empty/error states, ordering, stale request guards, and responsive widget tests pass. Authenticated first-card timing blocked. |
| Sport/site/category filters | `main_dashboard.dart`, category identity helpers | tested | Categories stay open, scroll horizontally, use sport-specific total facets, and do not collapse after selection. |
| Player search | API server search + Flutter search controls | tested | Search/clear and readiness checks pass; authenticated production journey blocked. |
| Player photos | resolver/widget + backend proxy/headshot services | tested | Resolver, URL-change stability, and readiness tests pass. Device/network decode timing not measured. |
| Prop alerts/bell | `main_dashboard.dart`, `prop_alert_inbox.dart` | fixed | Obsolete unread responses cannot restore a cleared badge; focused regression passes. |
| Provider ingestion | `python_backend/providers/*`, `raw_ingestion_service.py`, `sync_service.py` | tested | Local mocked provider/sync suite passes. Live quota/errors/logs blocked. |
| Normalization/identity | `prop_processor.py`, prop/category identity services | tested | Category, provider, identity, and invalid-row tests pass. No formulas changed. |
| Local catalog/cache | `database/cache.py`, catalog rebuild functions | tested | Empty/failed refresh and pruning tests pass. Live DB query plans blocked. |
| Redis publication | `distributed_cache_service.py` | tested | Atomic manifest/snapshot and late-publication tests pass. Live Redis memory unavailable. |
| Durable recovery snapshot | `prop_catalog_snapshot_service.py` | tested | Empty overwrite refusal, failure reporting, and reconciliation tests pass. |
| `/api/props` filtering/auth | `python_backend/main.py::props` | tested | Python suite passes; public readiness reports healthy catalog. Authenticated request capture blocked. |
| Scoreboard | controller/service/backend normalization | tested | Retry/preservation and wrong-league-logo tests pass. Live screenshot issue appears to predate current guarded code; deployment/device proof required. |
| Slips/tickets/grading/history | controllers, panels, backend slip routes | tested | Existing unit/widget/backend tests pass. Sandbox end-to-end settlement remains blocked. |
| Builder/research/watchlist | route widgets/services | tested | Existing functional and responsive tests pass. Full authenticated device journey blocked. |
| Chat | `prop_chat_page.dart`, chat service/backend routes | tested | Privacy/role/render tests pass. Live multi-user test not run. |
| Analytics/model tracking | analytics pages, prediction/settlement services | tested | Local tests pass; no prediction or grading formulas changed. |
| Owner/admin controls | owner/data-admin pages and protected endpoints | tested | Permission and responsive tests pass. No production admin action executed. |
| Billing/subscriptions | billing service, RevenueCat/store metadata tests | tested | Configuration/access tests pass. Apple sandbox purchase discovery remains blocked. |
| iOS platform | `ios/*`, entitlements/privacy metadata | tested | Static Apple tests pass. Archive/TestFlight/physical device validation blocked on this Windows host. |
| Android platform | `android/*`, Android workflow | inspected | Configuration inventoried; no emulator/release artifact executed in this audit. |
| Web/PWA | `web/*`, release web build | tested | Safe configured release build succeeds. Authenticated profile blocked by host certificate trust. |
| Render web/worker/cron | `render.yaml` | inspected | Web, Redis, worker, and six cron definitions inventoried. Live logs/metrics blocked without authenticated read-only integration. |
| Database migrations | SQL/scripts discovered in backend/operations history | inspected | No migration executed. Schema/index verification against live DB blocked. |
| Security/release gates | `tools/harden_release.py` | tested | Bandit, dependency audit, and debug-flag gates pass. |

## Verified prop path

`python_backend/providers/*` -> `raw_ingestion_service.py` ->
`sync_service.py` -> `prop_processor.py::process_and_cache_props` ->
`database/cache.py::PropCache` -> `distributed_cache_service.py` shared
catalog/manifest plus `prop_catalog_snapshot_service.py` recovery ->
`main.py::_cached_prop_catalog_singleflight` and `main.py::props` ->
`api_service.dart::_fetchPropPage` -> `prop_repository.dart` ->
`prop_sync_coordinator.dart` -> `prop_grid.dart` -> visible cards.

## Confirmed findings and fixes

1. **P1 request ownership across account changes** — fixed in `63e73e9`.
   An obsolete account request could remove the new account's in-flight slot.
2. **P1 false backend-offline result** — fixed in `63e73e9`. A protected
   `/api/props` health probe omitted authentication.
3. **P2 stale bell badge** — fixed in `63e73e9`. An older unread response could
   restore the badge after the inbox was opened.
4. **P2 release SDK prompt** — fixed in `63e73e9`. Successful OneSignal setup
   displayed sample integration UI in the native app.
5. **P1 CI false success risk** — fixed in `63e73e9`. Native exit codes now
   become terminating verifier failures.

## Latest executed checks

- `flutter analyze`: exit 0, no issues.
- `flutter test`: exit 0, 453 passed.
- `python -m pytest python_backend/tests -q`: exit 0, 1,221 passed.
- Focused regressions: exit 0, 30 passed.
- Safe configured `flutter build web --release`: exit 0.
- `python tools/harden_release.py`: exit 0.

## Blocked evidence

- Authenticated production network/performance trace, request count, and board
  payload size.
- Matched cold/warm login-to-first-visible and login-to-fresh-selectable prop
  measurements on iPhone, iPad, and desktop.
- Live Render API/worker logs, CPU/RAM, Redis peak memory, database pool/query
  plans, and refresh overlap.
- Apple sandbox subscription discovery and clean-install TestFlight journey.

The production domains presented a certificate chain this Windows host did not
trust. Public diagnostic requests succeeded only with verification disabled;
the browser warning was not bypassed and this is not sufficient evidence of a
production certificate defect.

## Next concrete task

Connect an approved read-only Render session and an authenticated staging or
device session. Reproduce one cold load with a non-personal test account and
record, for the same request: role/tier, filters, HTTP status, row counts,
catalog revision, provider-data timestamp, publication timestamp, receipt
timestamp, payload size, and first-visible/fresh-selectable timings. Then fix
the first boundary where those values diverge and add its regression before
any cosmetic work.

