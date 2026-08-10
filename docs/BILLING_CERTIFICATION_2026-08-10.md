# Billing Certification - 2026-08-10

## Verified live catalog

| Offering | Interval | Price | Trial | Entitlement | Status |
| --- | --- | ---: | ---: | --- | --- |
| Core | Monthly | $24.99 | 2 days | `core_tier` | Published |
| Core | Annual | $249.99 | 7 days | `core_tier` | Published |
| Pro | Monthly | $59.99 | 2 days | `edge_tier` | Published |
| Pro | Annual | $599.99 | 7 days | `edge_tier` | Published |
| Founding Pro | Monthly | $49.99 | 2 days | `edge_tier` | Published |
| Founding Pro | Annual | $499.99 | 7 days | `edge_tier` | Published |

RevenueCat offerings `core`, `edge`, and `edge_founding` each contain the expected monthly and annual packages for both Stripe production and Stripe sandbox applications. The application purchases these named offerings rather than the RevenueCat default test-store offering.

## Webhook verification

- The active webhook destination is `https://api.propsintell.com/api/billing/revenuecat/webhook`.
- An authorization header is configured.
- Both production and sandbox environments and all event types are enabled.
- RevenueCat displays successful historical deliveries.

## Automated verification

- Flutter billing, account-action, and subscription-required tests: 10 passed.
- Backend billing, RevenueCat, and Founding Pro tests: 7 passed.
- Production builds require a RevenueCat public API key.
- The server enforces a 100-member Founding Pro cap with transactional locking.

## Remaining manual gates

1. Archive the obsolete $29.99 Core and $89.99 Edge products in both Stripe production and sandbox after confirming they have no active subscribers.
2. Detach the obsolete products and retire the legacy RevenueCat entitlement.
3. Run sandbox purchase, renewal, restore, cancellation, expiration, and Core-to-Pro upgrade flows with dedicated test accounts.
4. Confirm Founding Pro reservations release correctly after abandoned checkouts and that the offering is retired when 100 active claims is reached.