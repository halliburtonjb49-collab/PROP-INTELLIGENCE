# PROP INTELLIGENCE Launch Checklist

## Billing and access

- [x] RevenueCat offerings `core`, `edge`, and `edge_founding` each expose active monthly and annual packages.
- [x] Monthly Core/Pro/Founding Pro products use $24.99/$59.99/$49.99 and a 2-day trial; every annual product uses a 7-day trial.
- [ ] Founding Pro distribution is capped at 100 claims in RevenueCat/Stripe and `edge_founding` is archived immediately after the cap is reached.
- [x] Entitlements are named `core_tier` and `edge_tier`.
- [x] `REVENUECAT_PUBLIC_API_KEY` is required by the Vercel production build and configured for the deployed web app.
- [x] RevenueCat webhook targets `https://api.propsintell.com/api/billing/revenuecat/webhook` with the configured authorization header; both production and sandbox events are enabled.
- [ ] New Core, Edge, renewal, restore, cancellation, and expiration flows are verified with sandbox accounts.

## Data and model integrity

- [ ] Historical and pregame cron jobs show successful recent runs.
- [ ] Production readiness has no missing tables.
- [ ] Predictions remain labeled experimental until 100 genuine pregame results are graded.
- [ ] No preview or synthetic market rows appear in production feeds.
- [ ] Odds freshness, player identity, availability, schedule, and officiating audits pass.

## User journey

- [ ] New account creation and email confirmation work from `app.propsintell.com`.
- [ ] Sign in, password reset, social auth, purchase, restore, upgrade, and sign out work.
- [ ] Core and Edge feature gates match the pricing descriptions.
- [ ] First-run onboarding appears once and can be completed at compact and desktop widths.
- [ ] Slip creation, saving, alert creation, and history work for the correct tier.

## Operations and release

- [ ] Owner launch-day control panel reports API, Redis, workers/queue, providers/quota, prop freshness, scoreboard latency, active users, failed payments, unsettled slips, and deployment version.
- [ ] Failed-login telemetry is connected from Supabase without exposing credentials or user identifiers.
- [ ] `PIPELINE_ALERT_WEBHOOK_URL` is configured for API and both cron services.
- [ ] `/health` returns `status: ok` and `/api/operations/pipelines` reports healthy runs.
- [ ] `python python_backend/scripts/production_smoke_check.py` exits successfully
  using the protected-feed readiness endpoint (the full prop feed must return
  `401` without a real user session).
- [ ] `python tools/harden_release.py` passes Bandit, dependency, and debug checks.
- [ ] Flutter analysis and tests pass; Python tests pass.
- [ ] Privacy policy, terms, responsible-play language, support email, and subscription disclosures are published.
- [ ] Release commit is deployed to the API, static app, historical sync, and pregame sync services.
