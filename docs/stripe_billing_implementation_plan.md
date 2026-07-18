# PROP INTELLIGENCE Stripe Billing implementation plan

Status: repository preparation complete; Stripe account and RevenueCat Stripe connection pending.

## Recommended architecture

Keep RevenueCat as the cross-platform entitlement authority and use Stripe Billing for web checkout, invoices, payment retries, tax configuration, and the Customer Portal. `core_tier` and `edge_tier` remain the application access contract. Do not add Stripe secret keys to the Flutter client or grant access directly from a checkout success redirect.

For `app.propsintell.com`, use identified RevenueCat web purchases so the checkout receives the signed-in Supabase user UUID as its App User ID. RevenueCat then maps the imported Stripe products to the existing `core` and `edge` offerings and notifies the existing authenticated backend webhook. The backend remains the only writer of `user_profiles.subscription_tier`.

## Stripe and RevenueCat account setup

1. Complete a Stripe sandbox account first, then connect it from RevenueCat as the RevenueCat project owner.
2. Create one flat-rate recurring Stripe product/price for Core and one for Edge. Use separate products for monthly and annual variants if both intervals are offered; RevenueCat recommends one selected price per imported Stripe product.
3. Configure invoice branding, customer emails, retry/dunning rules, tax behavior, statement descriptor, and support contact in Stripe.
4. Enable the Stripe Customer Portal for invoices, receipts, payment-method updates, plan changes, and cancellation. Put its URL in the RevenueCat Stripe web config.
5. Import the Stripe products into RevenueCat and attach them to packages in the existing `core` and `edge` offerings. Map them to `core_tier` and `edge_tier` respectively.
6. Create sandbox and production web purchase flows. Never expose or distribute the sandbox purchase URL to customers.
7. Register `app.propsintell.com` as a payment-method domain if checkout is launched by the RevenueCat Web SDK on the custom domain.

## Application work after account connection

1. Add the RevenueCat Web SDK or an identified hosted Web Purchase Link to the authenticated web paywall. URL-encode and pass only the current Supabase user UUID as the App User ID.
2. Add a backend-created management redirect or use RevenueCat `CustomerInfo.managementUrl`; never accept an arbitrary portal URL from the client.
3. Refresh RevenueCat customer info and backend session state after returning from checkout. Treat the webhook-updated backend profile—not the return URL—as authorization.
4. Show invoice/receipt and manage-subscription actions only when a trusted management URL exists.
5. Keep app-store purchase paths for platforms/regions where store policy requires them. Apply geo/platform eligibility rules before showing an external web purchase button.

## Webhook and data controls

- The RevenueCat webhook requires its bearer secret, an event ID, and event timestamp.
- `billing_webhook_events` provides replay protection without storing full customer payloads.
- `subscription_event_at` prevents delayed events from overwriting newer subscription state.
- Production logs must not contain authorization headers, checkout payloads, API keys, or complete invoice/customer objects.

## Verification and launch gates

1. In Stripe sandbox, test Core purchase, Edge purchase, upgrade/downgrade, cancel-at-period-end, expiration, failed payment/recovery, refund, and invoice/receipt access.
2. Verify each flow updates the correct RevenueCat entitlement and that duplicate/out-of-order webhook delivery does not regress access.
3. Confirm a checkout success page alone cannot unlock API features.
4. Confirm portal access is scoped to the signed-in customer and cannot be supplied by another user.
5. Re-run the same matrix with a low-value live transaction before enabling production links.

## Deliberately deferred

Stripe products, prices, portal settings, tax registrations, webhook endpoints, and secrets are not created by repository code. They must be configured after the correct Stripe account is created and connected. Direct Stripe Checkout should not be added alongside RevenueCat web checkout unless external-purchase tracking and a single entitlement authority are explicitly designed first.
