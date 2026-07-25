create table if not exists public.historical_player_game_logs (
  id text primary key,
  sport text not null,
  league text not null,
  event_id text not null,
  player_id text not null,
  player_name text not null,
  team_id text,
  game_date date not null,
  stats jsonb not null default '{}'::jsonb,
  source text not null,
  raw jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists historical_player_game_lookup_idx
  on public.historical_player_game_logs(sport, player_id, game_date desc);
create index if not exists historical_player_game_name_lookup_idx
  on public.historical_player_game_logs(sport, lower(player_name), game_date desc);

alter table public.historical_player_game_logs enable row level security;
drop policy if exists "authenticated historical player game reads"
  on public.historical_player_game_logs;
create policy "authenticated historical player game reads"
  on public.historical_player_game_logs for select to authenticated using (true);
