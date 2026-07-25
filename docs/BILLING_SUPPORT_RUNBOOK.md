# Billing support runbook

Use this procedure for refund, cancellation, failed-payment, and access requests.
Never ask a customer to send a full card number, security code, password, or
authentication token.

## Verify the customer

1. Ask the customer to write from the email address on the account.
2. Locate the customer in RevenueCat and Stripe using that email or the
   RevenueCat app user ID.
3. Confirm the current product, entitlement, purchase date, renewal date, and
   latest payment status before changing anything.
4. Record the request, UTC timestamp, reason, provider customer ID, action, and
   operator in the support log. Do not copy payment credentials into the log.

## Cancellation

1. Send the customer to **Manage subscription** in the app. The Stripe portal
   is configured to cancel at the end of the current billing period.
2. If the portal is unavailable, cancel at period end in Stripe.
3. Confirm the effective cancellation date in Stripe and RevenueCat.
4. Tell the customer that access remains active through the paid-through date.
5. After that date, confirm the RevenueCat entitlement expires and the app
   returns to the paywall.

## Refund

1. Review the published refund policy and the payment history.
2. If approved, issue the refund against the exact Stripe payment. Do not create
   an unrelated credit or cash transfer.
3. Decide whether access should end immediately or at period end and apply the
   matching subscription action.
4. Confirm Stripe shows the refund and RevenueCat reflects the intended
   entitlement state.
5. Send the customer the amount, date, expected bank processing window, and
   resulting access end date.

## Failed payment

1. Confirm Stripe's failed-payment email was sent.
2. Direct the customer to the Stripe portal to update the payment method.
3. Check Stripe's retry timeline and subscription status.
4. After recovery, confirm the invoice is paid and the RevenueCat entitlement
   is active.
5. If all retries fail, Stripe is configured to cancel the subscription.
   Confirm RevenueCat removes access when the cancellation/expiration event is
   processed.

## Escalation

Escalate when Stripe and RevenueCat disagree, a webhook delivery repeatedly
fails, a customer reports an unrecognized charge, or access remains wrong after
the provider state is corrected. Capture IDs and timestamps, but no secrets.
Do not promise a refund until the account and payment have been verified.
