begin;

-- These internal Owner Operations tables were originally created lazily by
-- the API. Keep their moderation state and audit history out of PostgREST.
alter table if exists public.owner_prop_quarantines enable row level security;
alter table if exists public.owner_prop_quarantines force row level security;
revoke all on table public.owner_prop_quarantines from anon, authenticated;

alter table if exists public.owner_alert_acknowledgements enable row level security;
alter table if exists public.owner_alert_acknowledgements force row level security;
revoke all on table public.owner_alert_acknowledgements from anon, authenticated;

alter table if exists public.owner_operations_audit enable row level security;
alter table if exists public.owner_operations_audit force row level security;
revoke all on table public.owner_operations_audit from anon, authenticated;

commit;
