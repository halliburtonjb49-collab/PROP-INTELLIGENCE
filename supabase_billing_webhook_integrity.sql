begin;

alter table public.user_profiles
  add column if not exists subscription_event_at timestamptz;

create table if not exists public.billing_webhook_events (
  provider text not null,
  event_id text not null,
  event_fingerprint text not null,
  app_user_id text not null,
  event_timestamp_ms bigint not null,
  received_at timestamptz not null default now(),
  primary key (provider, event_id)
);

revoke all on public.billing_webhook_events from anon, authenticated;

commit;
