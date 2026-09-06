# PI Sync Manager — Implementation Brief

Prepared September 6, 2026 for PI PROP INTELLIGENCE.

**Status:** Architecture and implementation requirements, not installed code. The observations below come from selected files retrieved from the repository's default branch. They do not establish what is deployed, which screens are active in production, or measured production performance. No repository files or live services were changed.

## Objective

Make the existing Flutter app show useful data promptly, deliver changed information without full-board disruption, and accurately distinguish fresh, delayed, cached, and unavailable information. Extend the current FastAPI, Redis, worker, and Flutter infrastructure. Do not add a competing provider-sync loop or replace the app's visual design.

The initial delivery should be a single shared client coordinator, version-based update notifications, and honest freshness state. A durable per-market delta protocol is a later optimization, justified by measurements rather than assumed necessary.

## What is already present

| Inspected file | Observed foundation | Implication |
| --- | --- | --- |
| `render.yaml` | FastAPI web service, Redis Key Value service, and an RQ background worker; configured fast, supplemental, and coverage refresh intervals of 120, 300, and 1,800 seconds. | Reuse the existing infrastructure. Check actual runtime configuration and job behavior before changing intervals or compute plans. |
| `python_backend/services/sync_service.py` | Fast-versus-coverage sports partitioning and provider quota-related integration. | Extend existing scheduling and quota controls rather than create an independent scheduler. |
| `python_backend/services/distributed_cache_service.py` | Compressed catalog publication, temporary-key construction followed by rename, and Redis write-error reporting. | Preserve complete-snapshot publication and bounded-memory processing. |
| `lib/services/api_service.dart` | In-flight page-request sharing, per-query successful results, persistent startup cache, authentication/session recovery, and feed-recovery metadata. | Build on the existing cache and authentication paths. Do not claim these features are absent. |
| `lib/widgets/prop_grid.dart` | First-page size of 24, session view caching, lifecycle observation, and a line-refresh timer. | Preserve responsive layouts, cached startup, and scroll position. A search result shows a 60-second line refresh. |
| `python_backend/tests/test_prop_delivery.py` | Tests for filtering/pagination, ETag behavior, and stable prop identity across a line change. | Preserve these contracts and run the tests; reading a test is not evidence it currently passes. |
| `python_backend/routers/realtime.py` | A props subscriber triggers catalog reads, model serialization, JSON construction and hashing every 10 seconds. A changed digest broadcasts the full list. | First optimization candidate: replace full-catalog scanning/broadcasting with small publication-version notifications. |

### Important issues to verify before rollout

The realtime route's authentication branch currently covers `tickets`, `alerts`, and `chat`, but not a props-only subscription. Before routing more customer traffic through it, require the same authentication and applicable entitlements as the protected HTTP prop feed. Confirm router mounting and production behavior in staging; no unauthenticated production probe was performed.

The realtime hub holds connections and its last digest in process memory. A new subscriber receives a connection acknowledgement but not necessarily a current props payload when the shared digest has not changed. Always give a new subscriber an explicit snapshot/revision synchronization path.

The API service stores several last-response counts and metadata fields as static values. Investigate cross-query and cross-account interaction. Prefer returning rows and their matching metadata as one immutable response object instead of reading a mutable global "last response" after an asynchronous request. This is a design risk to test, not a demonstrated production incident.

## Phase 1 — Shared state and a fast, correct board

Create or extend a session-scoped `PropRepository` and a `PropSyncCoordinator` using the app's current state-management approach. Do not introduce a new framework solely for this feature.

The repository owns immutable page state. Each page includes its query key, props, counts, provider coverage, recovery state, revision/validator, loading state, and freshness metadata. The coordinator owns transport, lifecycle, retries, and refresh decisions. Widgets render subscribed state; they do not independently coordinate equivalent network refreshes.

Query keys must include all response-shaping filters, sort, pagination, schema version, and relevant access scope. Scope persisted protected data to the account and entitlement context; clear or invalidate it at logout, account switch, and entitlement changes. A cache is not authorization.

Preserve the existing in-flight request sharing. When filters change, use a request-generation guard so a slower old response cannot overwrite the new view. Bundle counts with the response that produced them. Keep caches bounded with an eviction policy.

On first display, render the existing 24-item cached page only when it belongs to the current authorized scope. Label it accurately while checking the backend. If no usable cache exists, render card-shaped placeholders and load a small first page. Do not wait for every sport, history, headshot, or research panel before showing the board.

A refresh must preserve cards, filters, scroll position, expanded research, and ticket selections. Update changed card fields with narrow widget rebuilds. Maintain stable market identity across line changes, including correct differentiation of alternate offers. Do not reorder cards under the user's pointer while they are reading or selecting; provide an explicit way to apply ranking/order changes. Confirmed market suspensions and removals must still take effect promptly.

## Phase 2 — Small notifications instead of entire catalogs

Keep the existing WebSocket infrastructure after hardening its authentication and delivery behavior. Initially send only a small notification such as "the published MLB/PrizePicks view may have changed," then use the existing authenticated HTTP endpoint for the relevant filtered page.

The worker creates a new revision only after a complete valid snapshot is published. Reuse its existing publication pipeline. Store the revision and the referenced immutable snapshot consistently, so a client is never told to fetch a revision that is not readable yet. A shared monotonic sequence or an epoch-plus-sequence scheme must prevent a late older job from overwriting newer published state.

Do not derive revisions from an app release number, a WebSocket protocol version, or a repeatedly changing `served_at` timestamp. Content revisions and health/freshness status have different jobs. Unchanged values can still receive a new successful source-check time, but a cache read alone cannot advance that time.

Each API instance reads the small shared revision manifest or receives Redis notifications. Notifications are hints, not the only copy of state. Reconcile against the manifest after reconnect and periodically at a low rate. Redis Pub/Sub can lose messages during disconnects; a missed hint must not permanently strand a client on an old catalog. Reuse an existing reliable notification path if one is already integrated.

Make notifications interest-scoped: active sport/site views and relevant watched markets. Verify authentication and applicable entitlements before both subscription and HTTP delivery. Do not put credentials in URLs, disclose full provider error strings to customers, or expose privileged admin diagnostics.

Use existing ETag support end to end where appropriate. Associate each validator with the exact response/query and authorization scope. Unchanged conditional GETs should avoid retransmitting and decoding the page. Check the current `private, no-store` policy before adding persistent HTTP caching; do not weaken protected-feed access controls for speed. Review cross-origin request/response header configuration for custom validators. If policy requires no stored HTTP representation, use an application revision check rather than silently changing policy.

On first subscription and every resume/reconnect, compare revisions and reconcile an authorized snapshot. Do not depend on another line change to populate a newly connected client. Pause unnecessary updates while backgrounded and reconcile on foregrounding; do not promise uninterrupted PWA background execution.

Use bounded per-connection outbound queues and send deadlines, coalescing repeated invalidations when safe. A slow client must not block delivery to every other connection. Revalidate credentials when needed, handle token expiry, and release listeners/timers on sign-out and disposal.

### Optional later delta protocol

Only add per-market deltas after the simpler notification-plus-page approach is measured. A proposed envelope would include:

```json
{
  "schema_version": 1,
  "scope": "authorized-query-scope",
  "epoch": "publisher-generation",
  "base_revision": 1042,
  "revision": 1043,
  "upserts": [],
  "removed_ids": [],
  "resync_required": false
}
```

These fields are a proposed contract, not an existing API. Apply a delta only to its matching base revision and scope. Reject duplicates and older revisions. A missing history window, new epoch, or revision gap requires a fresh snapshot. Removals and suspensions must be explicit. A row leaving a filtered result is not necessarily a globally removed market. Ranked/paginated views must reconcile new entrants, displaced rows, and counts; patching only the rows already visible is insufficient.

## Freshness and trust contract

Store or map the following distinct concepts: provider-reported update time when available, last successful validation of the exact source/market, backend publication time, client receipt time, transport heartbeat, and model-context calculation time. Preserve originals when reading or restoring cached data.

Show freshness per source/sport/market rather than presenting the newest successful feed as proof all feeds are current. A connected socket or successful response from Redis does not establish that the underlying line is fresh. A 24-hour display-cache retention period is not permission to select a 24-hour-old line.

Use the existing stale-selection protections and extend them to additions from every screen. Before adding or reconfirming a selection, validate the current server-side market status and applicable freshness policy. If a line moved, show the new line and require confirmation. Keep the original recorded line of an existing ticket intact; display current-line comparisons separately. Do not silently rewrite a saved ticket.

An empty or malformed provider response must not erase unrelated valid data. On a failure, retain last-known data with accurate age and a visible delayed/recovery state; disable actions when policy requires it. A confirmed complete empty result, closed game, suspension, or removal must not be ignored indefinitely.

The public status component should support messages such as `Auto-updating`, `Updating`, `Provider delayed`, `Reconnecting`, and `Offline — showing saved data`. Example numbers must not ship as real health data. Distinguish "source last updated" from "we last checked" when the provider makes that distinction possible.

## Scheduling and reliability

Retain the current 120-second fast-provider setting initially while measuring. Increase priority near start time or for actively watched events only within the provider's documented cadence, coverage, subscription, and quota. The Odds API currently documents approximately 60-second intervals for its additional markets, including player props; calling it every second does not turn it into a per-second source.

Run source fetching centrally in workers, not once per viewer. Separate line ingestion/publication from slow research enrichment, historical backfills, grading, and image refresh. A newly confirmed line should not wait for a headshot or unrelated sport to finish. Reuse available projections when valid; mark a recommendation pending if changed inputs invalidate it rather than combining a new line with an unsupported old verdict.

Preserve bounded concurrency and add per-provider timeouts, retry budgets, exponential backoff with jitter, and `Retry-After` handling. Deduplicate equivalent queued jobs. Use distributed ownership/fencing where overlapping writers are possible. Do not use a process-local lock as proof of cross-service exclusion. Alert on loss of freshness rather than silently treating a failed publish as a successful sync.

Do not share process-local memory or `/tmp` SQLite files between Render services. Preserve the existing shared Redis and external durable-storage paths. Do not add a Redis flush or destructive cache rebuild as a normal user refresh action.

## Owner diagnostics

Add or extend an owner-only panel with last successful provider check, oldest actionable-market age by feed, job queue wait, ingestion duration, publication duration, API latency percentiles, publication-to-client delay, cache hit ratio, response bytes, Redis publication failures, and quota/rate-limit status. Keep sensitive details out of public status responses.

Owner actions should be authenticated, authorized, rate-limited, and audited. A scoped "refresh this sport" action queues deduplicated work and reports queued/running/published/partial/failed honestly. It must not trigger an unbounded full resync per click.

## Measurement and acceptance

Capture baseline and after-change measurements in release/profile builds on a representative phone, tablet, and desktop browser. Include both a first visit without cached Flutter assets and a returning session; do not use warm-session timings as a cold-start claim.

Suggested initial engineering targets, not observed results or guarantees:

- Useful cached board visible within 500 ms after the authenticated Flutter shell is ready on the agreed test device.
- Warm filtered-page API response below 300 ms at the 95th percentile under a defined test load.
- Published update applied to the active connected foreground view within 2 seconds at the 95th percentile; provider acquisition lag is measured separately.
- No full-board blanking, scroll reset, lost ticket selections, or complete-catalog WebSocket payload on an ordinary line change.

The test matrix must cover simultaneous identical requests; distinct query metadata; slow obsolete filter responses; account/entitlement switches; logout cache cleanup; protected WebSocket access; expired sessions; reconnect with unchanged data; dropped notifications; duplicate/out-of-order deltas if implemented; multiple API instances; slow clients; worker restart during publication; Redis failure; source timeouts and 429s; partial/empty feed failures; confirmed removals; game start/suspension; original ticket-line preservation; and stale selection attempts through every UI entry point.

Run existing backend prop-delivery tests and Flutter analyzer/widget tests, plus the new tests. Report actual results; never label unexecuted tests as passing. Roll out behind a feature flag, retain the existing delivery path for rollback, and compare latency, error rate, source age, and payload bytes before broad enablement.

## Coding-agent handoff

Inspect the current branch before editing because these files can change after this review. Map the active board and watchlist routes, then deliver Phase 1 and Phase 2 in small, reviewable changes. Reuse existing request sharing, auth recovery, stable IDs, ETag behavior, Redis publication, queues, and stale-selection protections. Do not change provider credentials, public pricing, sports coverage, user entitlements, or the app's navy/gold/silver layout. Do not commit directly to production as part of this brief. Provide changed files, executed test results, configuration changes actually required, and rollback instructions.

## Verification references

Repository files observed: `render.yaml`; `python_backend/services/sync_service.py`; `python_backend/services/distributed_cache_service.py`; `python_backend/routers/realtime.py`; `python_backend/tests/test_prop_delivery.py`; `lib/services/api_service.dart`; `lib/widgets/prop_grid.dart`. Default-branch file content was inspected; production configuration and performance were not measured.

Official technical references checked September 6, 2026:

- Flutter offline-first repository design: `https://docs.flutter.dev/app-architecture/design-patterns/offline-first`
- Flutter performance best practices: `https://docs.flutter.dev/perf/best-practices`
- MDN conditional HTTP requests: `https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Conditional_requests`
- MDN If-None-Match: `https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/If-None-Match`
- Redis Pub/Sub delivery semantics: `https://redis.io/docs/latest/develop/pubsub/`
- Render service types: `https://render.com/docs/service-types`
- The Odds API update intervals: `https://the-odds-api.com/sports-odds-data/update-intervals.html`
