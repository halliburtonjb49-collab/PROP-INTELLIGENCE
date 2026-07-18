# PROP INTELLIGENCE Launch Checklist

## Billing and access

- [ ] RevenueCat offerings `core` and `edge` each expose an active monthly package.
- [ ] Entitlements are named `core_tier` and `edge_tier`.
- [ ] `REVENUECAT_PUBLIC_API_KEY` is configured on the Render static app.
- [ ] RevenueCat webhook targets `https://api.propsintell.com/api/billing/revenuecat/webhook` with the configured bearer secret.
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

- [ ] `PIPELINE_ALERT_WEBHOOK_URL` is configured for API and both cron services.
- [ ] `/health` returns `status: ok` and `/api/operations/pipelines` reports healthy runs.
- [ ] `python python_backend/scripts/production_smoke_check.py` exits successfully.
- [ ] Flutter analysis and tests pass; Python tests pass.
- [ ] Privacy policy, terms, responsible-play language, support email, and subscription disclosures are published.
- [ ] Release commit is deployed to the API, static app, historical sync, and pregame sync services.
