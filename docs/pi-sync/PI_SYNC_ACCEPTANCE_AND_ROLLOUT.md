# PI Sync Manager — verification and rollout

This is a development checklist, not evidence of a completed installation. Only a reviewed implementation and executed tests can satisfy it.

## Local environment

Use the separate worktree and a test-only environment. The setup utility intentionally does not copy .env files, Supabase local JSON, virtual environments, ignored files, or uncommitted work. Do not solve missing test configuration by copying all production settings. Inspect the current test fixtures and import-time behavior first. Stop if a test would use a live database, provider, Redis, queue, billing, email, or production admin endpoint.

At the inspected commit, `.github/workflows/ci.yml` uses Python 3.12 and installs `requirements.txt` plus `requirements-dev.txt`. It supplies `ODDS_API_KEY=ci-placeholder` and `API_SPORTS_KEY=ci-placeholder` for mocked tests. Recheck current CI before selecting versions. Add any newly required placeholders only after verifying that outbound calls are mocked. A placeholder alone is not network isolation.

Typical commands for the coding agent, from the feature worktree, after isolating configuration:

```powershell
# Use the project's supported Python and a separate local virtual environment.
# Installing dependencies requires a normal package-network connection.
py -3.12 -m venv .venv
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt -r requirements-dev.txt

# Run only in an inspected, mocked test environment with no live service credentials.
$env:ODDS_API_KEY = 'ci-placeholder'
$env:API_SPORTS_KEY = 'ci-placeholder'
& .\.venv\Scripts\python.exe -m pytest python_backend/tests -q

flutter pub get
flutter analyze
flutter test --concurrency=1
```

Check native-command exit codes; PowerShell does not universally stop on a failing native command. The above is a reference sequence, not an automatic production script. If the Python launcher/version is not installed, use the compatible project interpreter rather than installing a different one blindly. Run focused tests during editing and the full CI matrix before release. The current CI also checks release hardening and builds web/Android; consult the workflow for its complete, up-to-date gates.

Use `flutter build web --release` with the existing verified non-secret build configuration for validation. CI placeholder Supabase values create a compilation test, not a login-capable production bundle. Do not publish that bundle. Existing hosting/build tooling, not a generic standalone command, must supply actual deployment configuration.

## User-visible acceptance matrix

| Case | Required behavior |
| --- | --- |
| First open without cache | Small initial page; stable placeholders; do not wait for all research or sports. |
| Returning authorized session | Correctly scoped cached content remains clearly labeled while validating. |
| A single line changes | Relevant values update; no full-board blanking, top-of-page jump, or lost ticket. |
| Rapid MLB/WNBA/site/filter changes | Last requested view wins; rows/counts/coverage all match that same query. |
| Several views need one page | One shared request, not a fetch per listener. |
| Page 2 while rankings change | Consistent pagination/facets and new entrants; no silent duplicate/missing rows. |
| Sign-out, account switch, entitlement downgrade | Old protected cache cannot display or reappear from late requests. |
| Source stale but socket connected | Delayed source status; unsafe selections remain blocked. |
| Offline or reconnecting | No false "live" label; preserve data appropriately and reconcile on return. |
| New subscriber when data is unchanged | Gets a current snapshot/revision without waiting for the next line move. |
| Dropped/out-of-order hint | Reconciliation recovers; no regression to older state. |
| Confirmed suspension/removal/start | Selection/actionability changes promptly in every entry point. |
| Saved ticket has old line | Recorded ticket line stays intact; only current-line comparison changes. |
| Redis/provider failure or worker restart | No invalid empty publish; accurate delayed/error state and bounded retries. |
| Slow WebSocket client/multiple API instances | One client does not block others; revision source is shared, not process-local. |
| Old/new client/backend pairings | Authenticated compatible fallback; no entitlement bypass. |
| Desktop, tablet, phone | Existing navy/gold/silver layout remains usable with no clipping or jank regression. |

Source timestamp, last successful source check, publication time, and client receipt time are different. Verify all four where available. Do not claim a two-second source update when only the delivery leg was measured.

## Proposed measured targets

These are goals, not promises or observed results: cached board within 500 ms after an authenticated shell is ready on the chosen representative device; warm filtered API p95 under 300 ms at a defined load; publication-to-active-client p95 under 2 seconds on the new transport. Measure cold startup separately. Use profile/release measurements, not only debug mode.

Record baseline and after-change payload bytes, request counts, API/error latency, source age, memory, and delivered updates. For Stage B's new path, ordinary notifications must not carry the entire catalog. Legacy compatibility behavior must be documented honestly until retired.

## Release order — not automatic authorization to deploy

1. Review Stage A code and tests on its feature branch. Run the app in a local/test environment with the flag on and off. Do not merge just to obtain the first test run.
2. Review Stage B/C independently. If using a shared staging environment, obtain authorization before creating paid services or using staging credentials. A source-code branch alone does not isolate production services.
3. Before any approved merge, inspect service-linked branches, build/deploy triggers, GitHub workflows, and whether all workers/API/frontend will deploy the same reviewed commit. Do not assume Render dashboard settings match YAML. Record current deployed versions and rollback settings.
4. Deploy backward-compatible, secure backend support before enabling the new frontend path. Authentication protections remain on in all modes. Test old/new version combinations. Keep new features default-off until readiness is verified.
5. Enable for an authorized test/owner cohort using the actual implemented flag mechanism, then expand after successful checks. A compile-time Flutter flag needs a new frontend build; rebuilding the backend cannot toggle it.
6. After release, use the existing protected production checks with authorized secrets in their existing environment. At the inspected commit, `Deploy to Production` runs on main pushes and invokes `tools/post_deploy_smoke.py` expecting the exact Git SHA. This checks deployment; it is not proof that all services actually auto-deploy correctly.

## Rollback

Before rollout, document the exact disabled feature state and last-known-good frontend/API/worker commit(s). A rollback must keep the authentication hardening, preserve saved tickets, and avoid credential/DB/cache destruction. Disable the new performance path and use authenticated HTTP fallback when compatible. Client compile-time flags require redeployment of a compatible build.

If a commit rollback is needed, use a reviewed revert/known-good deployment, not `git reset --hard`, a force push, Redis flush, or a schema drop. Verify Render automatic-deploy behavior when deploying a specific older commit, or a later push may replace that rollback. Reconcile all service versions. Never restore a known unauthenticated prop endpoint as the rollback path.

## Official references

- Flutter repositories/offline-first: https://docs.flutter.dev/app-architecture/design-patterns/offline-first
- Flutter app architecture: https://docs.flutter.dev/app-architecture/guide
- Git worktrees: https://git-scm.com/docs/git-worktree
- Render deployment behavior: https://render.com/docs/deploys
- Render rollbacks: https://render.com/docs/rollbacks

These are implementation references, not production measurements.
