# Implement PI Sync Manager in this workspace

Prepared September 6, 2026. This is an executable-work handoff for a coding agent, **not implemented application code**. The setup script only creates a Git worktree and copies instructions. The agent must edit the actual Dart/Python code, add tests, and produce diffs.

## Task and authorization

Implement the PI Sync Manager in the feature-branch workspace currently open. Read `PI_Sync_Manager_Implementation_Brief.md` and `PI_SYNC_ACCEPTANCE_AND_ROLLOUT.md` in this directory. Follow the repository's own agent instructions and current implementation. Inspect current files before editing; the repository can be newer than this review.

Default scope for the first execution is **Stage A**. Complete an integrated, testable vertical slice instead of disconnected helper files. Do not stop after writing another plan. Do not commit, push, merge, trigger workflows, deploy, modify Render/Supabase settings, or access production systems. Do not touch the original project worktree. You may edit and test files within this development worktree.

Do not copy or print production credentials. Unit tests must mock outbound providers, databases, Redis, WebSockets, and HTTP as appropriate. Do not launch ingestion or background jobs against production for a test. Inspect import-time side effects before importing the backend. A separate Git worktree isolates files, NOT remote resources; never treat a new folder as a sandboxed database.

## Inspection baseline

Repository `halliburtonjb49-collab/PROP-INTELLIGENCE`; main inspected at `57f3caff2604c94b26895d433d229278dbe2a256`. The setup script records the actual fetched base in `SETUP_CONTEXT.md`.

Observed entry points (not a complete runtime trace):

- `lib/widgets/main_dashboard.dart` constructs `PropGrid`.
- `lib/widgets/prop_grid.dart` has its own line-refresh path and cache; a retrieved search excerpt shows a 60-second refresh timer. It also enforces `prop.isSelectable && !prop.dataStale` on card actions. Preserve these protections.
- `lib/services/api_service.dart` already handles authenticated fetches, auth recovery, shared in-flight requests, cached responses, filtering, and response metadata. Several last-response metadata fields were static in the prior inspection. Confirm current behavior and tests rather than blindly replacing it.
- `lib/services/live_update_service.dart` already connects to `/api/realtime/ws`, handles `authentication.required`, and reconnects with backoff. It is named **LiveUpdateService**, not LiveUpdatesService. Reuse and harden it; do not introduce a second equivalent connection per screen.
- `python_backend/routers/realtime.py` is the existing hub. The prior review found full-catalog serialization/broadcasting and an authentication branch that did not include a props-only subscription. Recheck the current code, routes, and entitlements. This is a code observation, not proof of a live exposure.
- `python_backend/services/distributed_cache_service.py` already performs bounded/compressed publication and records Redis errors. Reuse it and trace all actual publisher call sites.
- Existing tests include `test/prop_grid_test.dart`, `test/board_cache_test.dart`, `python_backend/tests/test_prop_delivery.py`, and `python_backend/tests/test_realtime_api.py`.
- `.github/workflows/ci.yml` includes Python tests, release hardening, Flutter analysis/tests/web build, and Android build. Do not delete or weaken these checks.
- `.github/workflows/deploy-production.yml` runs on pushes to main and checks production with `tools/post_deploy_smoke.py`. It relies on service deployment; do not mistake it for a separate frontend upload command. Do not run this production smoke workflow during development.

Resolve active mobile/tablet/desktop shells and watchlist routes by inspecting the current source. Do not edit backup files or unused alternative screens as a substitute for the active UI.

## Stage A — Integrate shared, consistent Flutter prop state

First record the baseline, relevant tests, and current request graph. Then implement this stage in actual project files.

### Public API/result contract

Create or extend a typed immutable page result (suggested `lib/models/prop_page.dart`) containing rows, query identity, pagination, counts/facets, coverage, response provenance/recovery status, and available timestamps/validators. Deep-copy or freeze mutable collections. Keep each page's metadata with its own rows; do not await a fetch and then read unrelated mutable global "last response" metadata.

Expose a typed `fetchPropPage`-style path in `ApiService` using the existing authentication, parsing, request-sharing, error classification, and HTTP calls. Retain a compatible `fetchProps` adapter for callers not migrated yet. Do not change the meaning of existing filters or lose hidden query fields. If in-flight sharing currently uses only URL, review account/session sharing before retaining it.

Add an exact query value/key including all response-shaping filters, sort, page/cursor, schema, and access scope. Do not use a bearer token as a logged/cache key. Session/account/entitlement changes must invalidate protected memory/persistent caches and obsolete in-flight requests. Do not delete unrelated user data. An old-account request must never repopulate cache after sign-out or contaminate a new session.

### Repository and coordinator

Suggested files: `lib/services/prop_repository.dart` and `lib/services/prop_sync_coordinator.dart`. Reuse the current state-management approach; do not add Riverpod, Bloc, SQLite, or another dependency just for this change.

Own one repository/coordinator per authenticated app session and inject it into active consumers. Cache a bounded set of immutable page results. Deduplicate identical requests and coalesce bursts of invalidations. Preserve cached rows while refreshing. Use generation/query guards for filters, account switches, refreshes, load-more, and subscriptions. Drop obsolete responses before changing rows OR counts OR freshness.

Subscribe/unsubscribe with reference counting. Remove replaced widget timers only after their responsibilities move into the coordinator. Preserve refresh semantics for unmigrated screens. Do not leave both old and new timers polling the same active view. Stage A can use an HTTP reconciliation timer through the coordinator; it does not need the Stage B server contract yet.

On backgrounding, pause unnecessary network work and timers. On resume, reconcile once, sharing simultaneous requests. Serialize lifecycle transitions; a late disconnect callback from an old connection must not clear a new socket. Release listeners/timers on sign-out and disposal. Do not promise continuous background PWA execution.

### Integrate active views, not just helpers

Wire the active board (`main_dashboard`/`prop_grid` and applicable shells) to subscribed typed state behind a default-off feature flag. Migrate active watchlist/current-market consumers where equivalent prop data is used, without forcing every screen into the same query or fetching every sport to support a small selection.

Do not rewrite saved-ticket line values with live-market values. Preserve original recorded lines and display current comparisons separately. Keep server validation and stale/suspension gating for every new selection entry point, not merely the main board.

Use stable market/card keys. Refresh must preserve scroll, selected tickets, open research, filter state, and images where identity is unchanged. Do not re-rank cards under a user's pointer; an explicit "updated rankings available" action is acceptable. Apply safety removals/suspensions without waiting for ranking approval. Reconcile pagination/new entrants and facets correctly; pinning visual order is not permission to retain invalid selections.

Add a small status component using existing colors/tokens. Only display measured state: Checking, Updating, Provider delayed, Reconnecting, or Offline/saved data when that condition is actually known. Socket connectivity and client receipt time must not be labeled as a recent source check. Never ship example freshness numbers.

### Stage A completion gate

Compile the integrated app and run focused tests plus `flutter analyze` and the existing Flutter suite where available. Add tests for query metadata isolation, deduplication, cache bounds, old-response races, authentication/account invalidation, lifecycle, no blank-board refresh, scroll/selection preservation, and unchanged original ticket lines. Test both feature-flag states. Report blocked/unrun tests honestly. Leave Stage B transport changes for the next reviewed stage.

## Stage B — Authenticated publication hints, not full-catalog pushes

Execute this stage after Stage A is reviewed and its tests are green. Follow the full brief; these requirements add integration specificity.

Trace the RQ worker -> accepted catalog publication -> shared Redis -> API read path. Reuse existing source ingestion and queues. Publish a small shared revision manifest only with an accepted complete catalog. A revision must reference a readable snapshot consistently. Atomic pointer/snapshot publication and ordering must prevent a superseded/late writer from reverting newer data. Do not use process-local memory as the shared source of truth. Do not generate versions from APP_VERSION, protocol version 1, or cache read time.

Keep content revision separate from source-health/source-check state. Unchanged lines can have newer successful source validations, but cache access cannot advance that validation. Ensure HTTP page responses and conditional validators are tied to the actual snapshot served, not an independently read newer manifest. Design validation of stale market/actionability around time as well as content.

Extend the existing realtime transport with a negotiated v2 invalidation mode or additive channel/route. Notifications contain only minimal, authorized hints and revision context. For the first implementation, a single global manifest hint followed by scoped HTTP reconciliation is acceptable; label this honestly instead of claiming precise per-sport invalidation. Optimize interest scoping when supported by publisher data.

Authenticate props subscriptions and enforce the protected feed's applicable entitlements. Reuse the auth recovery path in the client, bound handshake time, validate token expiry/changes, and never send tokens in a URL. Protect all prop-delivery paths even when the performance feature flag is off. Legacy protocol compatibility must not preserve unauthenticated access.

Serve old-client compatibility explicitly while rolling out new clients; do not silently replace `props.updated` full rows with an incompatible payload. New clients may fall back to authenticated HTTP, not an unprotected endpoint. The v2 path must not scan/serialize the entire catalog every ten seconds. Publish from the worker or read the SMALL shared manifest. Do not add another provider-fetch loop in the API server or browser.

On subscribe, connect, resume, and reconnect, return/read the current revision and reconcile a snapshot even when no new change occurs. Use low-rate reconciliation to recover missed notifications. Per-client queues and send timeouts must prevent one slow client from blocking others. Catch and report sanitized failures without revealing provider credentials/errors.

Use existing ETags only after verifying exact query/auth scope and cross-origin headers. Do not weaken the current private/no-store policy as an incidental speed fix; use an explicit application revision check when stored HTTP representation is disallowed. Cache validation must not imply fresh source data. Do not start a durable per-prop delta protocol in this stage unless the simpler approach is inadequate and measured.

Add backend tests for auth, entitlement parity, initial unchanged subscription, manifest/catalog consistency, rejected old publishers, reconnect/missed hints, multiple API instances, slow clients, Redis failure, old-client behavior, and version-scoped HTTP validation. Add client tests for both transports and authentication lifecycle. Use mocks/local test services only.

## Stage C — Broader information syncing and owner health

Only after Stage A/B correctness is reviewed: extend the existing scheduling/priority controls and owner diagnostics. Do not replace the existing worker or add per-member source fetching. Keep the current 120-second fast provider interval initially. Verify current runtime/provider capabilities before altering it.

Prioritize near-start and actively watched events within quota. Reuse job deduplication, bounded workers, provider timeouts, retry budgets, jitter and Retry-After. A failed/partial source must not erase unrelated valid data. A confirmed complete removal or suspension must not be kept selectable indefinitely.

Separate expensive headshots, history, grading, and other enrichment from timely line publication. New lines with invalidated model inputs require a pending/unavailable recommendation, not an old verdict attached to a new line. Extend schedules/scores/injuries/lineups with separate domain state and true per-source freshness where the current app exposes those features. Do not put chat, ticket history, all scores, and raw odds into one global prop payload.

Extend the current owner view, rather than adding duplicate dashboards. Display only collected metrics: source age/check, queue wait, publication duration/errors, API latency, response bytes, and provider quota. Measure publication-to-screen separately from provider latency. Protect, authorize, rate-limit and audit any scoped refresh action. Do not change infrastructure plans, business pricing, sports coverage, credentials, or model formulas without separate authorization.

## Feature-flag contract

Reuse an existing suitable feature-flag mechanism. Otherwise proposed names are `PI_SYNC_MANAGER_ENABLED` (Flutter) and `PI_PROP_REVISION_FEED_ENABLED` (backend), default false. These names do not exist merely because this document proposes them. Implement and test the gates before asking the user to set them. A compile-time Dart define requires a new frontend build; a server setting does not instantly flip that client build. Authentication fixes are not optional flags.

Test old/new frontend and backend combinations. Retain authenticated fallback behavior for rollback. Do not enable new transport for all members before coordinated deployment and verification.

## Required output for each stage

Write `docs/pi-sync/IMPLEMENTATION_RESULTS_STAGE_A.md` (or B/C) with: actual base commit; active routes integrated; changed files and contracts; tests actually executed and exact outcomes; unavailable tests and why; changes not yet implemented; feature-flag names/defaults proven in code; any required non-secret settings; build/preview commands that match the project's real setup; and specific rollback instructions. Include a concise diff summary in the agent's final response.

Do not report generated files as installed/deployed. Do not invent passing tests, load metrics, or a production speed improvement. Stop before commit/push/merge/deploy.
