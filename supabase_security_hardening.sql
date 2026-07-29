begin;

-- The public schema is exposed by PostgREST. Every table in it must have RLS,
-- including operational tables that intentionally have no client policies.
do $$
declare
  table_row record;
begin
  for table_row in
    select tablename
    from pg_tables
    where schemaname = 'public'
  loop
    execute format(
      'alter table public.%I enable row level security',
      table_row.tablename
    );
  end loop;
end
$$;

-- Proprietary model inputs and outputs are served only by the authenticated
-- API. A browser must never query these tables directly.
revoke all on public.billing_webhook_events from anon, authenticated;
revoke all on public.sportsbook_line_snapshots from anon, authenticated;
revoke all on public.prop_market_intelligence from anon, authenticated;
revoke all on public.prediction_snapshots from anon, authenticated;
revoke all on public.player_stretch_embeddings from anon, authenticated;
revoke all on public.player_fatigue_features from anon, authenticated;
revoke all on public.officiating_tendency_profiles from anon, authenticated;
revoke all on public.team_matchup_profiles from anon, authenticated;

drop policy if exists "read historical analogs"
  on public.player_stretch_embeddings;
drop policy if exists "authenticated prediction reads"
  on public.prediction_snapshots;
drop policy if exists "authenticated fatigue reads"
  on public.player_fatigue_features;
drop policy if exists "authenticated officiating reads"
  on public.officiating_tendency_profiles;
drop policy if exists "authenticated matchup profile reads"
  on public.team_matchup_profiles;

create table if not exists public.security_events (
  id bigserial primary key,
  occurred_at timestamptz not null default now(),
  event_type text not null,
  actor_hash text,
  route text,
  method text,
  outcome text not null,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists security_events_occurred_at_idx
  on public.security_events(occurred_at desc);
create index if not exists security_events_type_idx
  on public.security_events(event_type, occurred_at desc);

alter table public.security_events enable row level security;
alter table public.security_events force row level security;
revoke all on public.security_events from anon, authenticated;

commit;
