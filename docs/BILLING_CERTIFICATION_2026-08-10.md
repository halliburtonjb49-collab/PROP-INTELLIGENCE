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

## Catalog cleanup evidence

- Stripe production now has six active current products and two archived legacy products. Archived: Core `prod_UuTVP3qqOCvRlO` ($29.99) and Edge `prod_UuTVdDFP06Xe4H` ($89.99). Both had zero active subscriptions before archival.
- Stripe sandbox now has six active current products and two archived legacy products. Archived: Core `prod_UuPICla4aEyHMN` ($29.99) and Edge `prod_UuPJXMtrbZQAtU` ($89.99). Existing test subscriptions were preserved.
- The four archived products were detached from RevenueCat. `core_tier` now contains four current live/sandbox products; `edge_tier` contains eight current Pro/Founding live/sandbox products.
- The unused `PI PROP INTELLIGENCE Pro` Test Store entitlement (`entl787b5a5265`) was deleted.

## Sandbox lifecycle evidence

- Dedicated customer: `billing-cert-20260810@example.com` / `PI Billing Certification`.
- Subscription: `sub_1U2zvHR1fSazv4UPpX4JrSTz`.
- Created a Core Monthly $24.99 subscription with a two-day trial.
- Upgraded the active trial to Pro Monthly $59.99; the two-day trial remained attached.
- Advanced the Stripe sandbox clock past trial end. Stripe generated the $59.99 post-trial invoice and moved the subscription to `Past due`, as expected because the synthetic customer had no payment method.
- Scheduled cancellation and advanced the sandbox clock. The subscription reached `Canceled` with an `Ended at` timestamp.

This Stripe-dashboard lifecycle validates catalog pricing, trial creation, upgrade, invoice generation, failed-payment state, and cancellation/expiration. It does not certify RevenueCat SDK purchase or restore because the synthetic subscription was created directly in Stripe and therefore had no RevenueCat app-user identity.

## Remaining manual gates

1. Run RevenueCat SDK purchase and restore from a dedicated signed-in app test account, including a successful renewal with a Stripe test payment method.
2. Confirm Founding Pro reservations release correctly after abandoned checkouts and that the offering is retired when 100 active claims is reached.