# Production launch audit — July 25, 2026

## Verified

- Production prop feed health reports `ok` and a successful provider request.
- The actionable feed excludes past and started events. The production check
  found 60 expired/started rows in the diagnostic feed and zero in the
  actionable feed.
- The five-minute watchdog and 45-minute stale threshold are configured.
- The latest pregame pipeline run succeeded with zero failed provider events.
- RevenueCat webhook authentication is configured and two webhook deliveries
  are persisted in `billing_webhook_events`.
- Automated subscription contracts cover purchase/renewal tier mapping,
  cancellation through the paid period, billing-issue grace access, expiration,
  duplicate protection, and stale-event ordering.
- Password-recovery link detection, password validation, account billing
  actions, and billing configuration tests pass.
- Mobile phone/tablet tests pass for login, recovery, application shell,
  navigation drawers, PROP CHAT, and primary workspace destinations.
- `propsintell@gmail.com` is the published support address and
  `docs/BILLING_SUPPORT_RUNBOOK.md` covers cancellation, refunds, failed
  payments, verification, and escalation.

## Launch blockers requiring account configuration

- Configure `PIPELINE_ALERT_WEBHOOK_URL` on the API, historical-sync cron, and
  pregame-sync cron. The destination must be an owner-monitored alert channel.
- Configure `REVENUECAT_CORE_PRODUCT_IDS` and
  `REVENUECAT_EDGE_PRODUCT_IDS` on the API using the exact RevenueCat product
  identifiers. Entitlement-based events work, but product-only webhook events
  need this fallback mapping.
- Confirm Supabase scheduled backup retention in the Supabase dashboard and
  perform one documented restore rehearsal before launch.
- Confirm `propsintell@gmail.com` is actively monitored and send a test support
  request through the published customer path.
- Run one provider-sandbox lifecycle with a disposable account: Core purchase,
  Pro upgrade, cancellation at period end, billing failure/recovery,
  expiration, restore purchase, and password recovery. Record the RevenueCat
  event IDs and resulting app access state without storing credentials.

## Monitoring interpretation

`/api/operations/pipelines` considers each pipeline's latest run authoritative.
Older failures remain in `recentFailures` for investigation but no longer keep
the service unhealthy after a successful recovery.

`/api/operations/acceptance` reports persisted RevenueCat webhook delivery
count and the last received timestamp without exposing customer or payment
data.
