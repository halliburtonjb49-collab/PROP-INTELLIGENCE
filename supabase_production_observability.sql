alter table public.prop_engagement_events
  add column if not exists duration_ms integer,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.prop_engagement_events
  drop constraint if exists prop_engagement_events_action_check;

alter table public.prop_engagement_events
  add constraint prop_engagement_events_action_check check (action in (
    'VIEW','SEARCH','CLICK','WATCHLIST','PICK_OVER','PICK_UNDER','APP_OPEN',
    'ONBOARDING_COMPLETE','ONBOARDING_SKIPPED','DASHBOARD_READY','SITE_FILTER',
    'VERDICT_FILTER','PROP_SELECTED','SLIP_LOCKED','PAYWALL_VIEW',
    'CHECKOUT_STARTED','CHECKOUT_FAILED','PURCHASE_COMPLETED','SLOW_LOAD','ERROR',
    'API_SUCCESS','API_FAILURE','PROP_LOAD_SUCCESS','PROP_LOAD_FAILURE',
    'AUTH_FAILURE','MEDIA_FAILURE','SERVICE_WORKER_VERSION','SCREEN_TIMING','WEB_VITAL',
    'LANDING_VIEW','SIGNUP_STARTED','EMAIL_VERIFIED','FIRST_PROP',
    'PI_INTELLIGENCE_OPENED','RETURNING_USER'
  ));

create index if not exists prop_engagement_observability_idx
  on public.prop_engagement_events(action, created_at desc)
  where prop_id='__OBSERVABILITY__';
