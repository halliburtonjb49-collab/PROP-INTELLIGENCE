# Post-launch UX backlog

Prioritize these items using production performance, support reports, and
feature-usage evidence. Do not expose credentials, raw authentication events,
or private user content in analytics or problem reports.

## P0: speed, feedback, and recovery

1. Faster first load and scoreboard display
   - Record web startup and scoreboard latency percentiles.
   - Improve the slowest measured path before adding speculative caching.
2. Skeleton loaders
   - Replace blank feed, scoreboard, and paywall waits with layout-stable
     skeleton states.
3. Freshness labels
   - Show `Updated X seconds/minutes ago` using the server timestamp.
   - Recompute the relative label without refetching the dataset.
4. Delayed-provider status
   - Show a visible degraded-data banner when a provider or feed is stale.
   - Preserve the last safe dataset and timestamp.
5. One-tap retry
   - Retry the failed request without clearing sport, book, market, search,
     filters, selected props, or the active slip.

## P1: continuity and personalization

6. Search history and recently viewed players
   - Store a bounded per-user history with clear/remove controls.
7. Favorites
   - Support favorite players, teams, and prop categories across sessions.
8. Notification controls
   - Allow independent controls for tickets, sports, and chat categories.
9. First-time walkthrough
   - Keep it short, dismissible, accessible, and shown only once unless reset.

## P1: support

10. In-app Report a Problem
    - Include page/route, application version, platform, and timestamp.
    - Let the user review the report before sending.
    - Never include access tokens, passwords, payment details, chat content,
      prop selections, or other private data automatically.
