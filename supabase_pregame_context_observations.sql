create table if not exists public.pregame_context_observations (
  id uuid primary key default gen_random_uuid(),
  sport text not null,
  event_id text not null,
  provider text not null,
  entity_type text not null,
  provider_player_id text not null default '',
  player_name text not null default '',
  team text not null default '',
  opponent text not null default '',
  event_time timestamptz,
  observed_at timestamptz not null default now(),
  status text not null default '',
  confirmed boolean not null default false,
  fingerprint text not null,
  payload jsonb not null default '{}'::jsonb,
  unique(provider, fingerprint)
);

create index if not exists pregame_context_player_idx
  on public.pregame_context_observations(sport,lower(player_name),observed_at desc);
create index if not exists pregame_context_event_idx
  on public.pregame_context_observations(sport,event_id,observed_at desc);

alter table public.pregame_context_observations enable row level security;
revoke all on public.pregame_context_observations from anon, authenticated;
