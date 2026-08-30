alter table public.prop_engagement_events
  drop constraint if exists prop_engagement_events_action_check;

alter table public.prop_engagement_events
  add constraint prop_engagement_events_action_check check (action in (
    'VIEW', 'SEARCH', 'CLICK', 'WATCHLIST', 'PICK_OVER', 'PICK_UNDER',
    'APP_OPEN', 'ONBOARDING_COMPLETE', 'ONBOARDING_SKIPPED',
    'DASHBOARD_READY', 'SITE_FILTER', 'VERDICT_FILTER', 'PROP_SELECTED',
    'SLIP_LOCKED', 'PAYWALL_VIEW', 'CHECKOUT_STARTED', 'CHECKOUT_FAILED',
    'PURCHASE_COMPLETED', 'SLOW_LOAD', 'ERROR'
  ));
