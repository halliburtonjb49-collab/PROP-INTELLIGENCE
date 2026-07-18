create table if not exists public.historical_basketball_game_logs (
  id text primary key, sport text not null check (sport in ('NBA','WNBA')),
  league_game_id text not null, player_id text not null, player_name text not null,
  team_id text, game_date date, matchup text, minutes double precision,
  points double precision, rebounds double precision, assists double precision,
  steals double precision, blocks double precision, turnovers double precision,
  threes double precision, personal_fouls double precision, free_throw_attempts double precision,
  raw jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists basketball_player_market_idx
  on public.historical_basketball_game_logs(sport, player_id, game_date desc);

create table if not exists public.historical_mlb_pitches (
  id text primary key, game_pk text not null, game_date date,
  pitcher_id text, batter_id text, umpire text, pitch_type text, description text,
  plate_x double precision, plate_z double precision, release_speed double precision,
  sz_top double precision, sz_bot double precision,
  events text, home_team text, away_team text,
  raw jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now()
);
create index if not exists mlb_pitcher_date_idx on public.historical_mlb_pitches(pitcher_id, game_date desc);
create index if not exists mlb_umpire_date_idx on public.historical_mlb_pitches(umpire, game_date desc);
alter table public.historical_mlb_pitches add column if not exists sz_top double precision;
alter table public.historical_mlb_pitches add column if not exists sz_bot double precision;
alter table public.historical_basketball_game_logs add column if not exists personal_fouls double precision;
alter table public.historical_basketball_game_logs add column if not exists free_throw_attempts double precision;

create table if not exists public.basketball_official_game_assignments (
  sport text not null check (sport in ('NBA','WNBA')), league_game_id text not null,
  official_id text not null, official_name text not null, game_date date,
  total_fouls double precision not null, total_free_throw_attempts double precision not null,
  raw jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now(),
  primary key(sport, league_game_id, official_id)
);
create index if not exists basketball_official_history_idx
  on public.basketball_official_game_assignments(sport, official_id, game_date desc);
alter table public.basketball_official_game_assignments enable row level security;
drop policy if exists "authenticated basketball official reads" on public.basketball_official_game_assignments;
create policy "authenticated basketball official reads" on public.basketball_official_game_assignments
  for select to authenticated using (true);

alter table public.historical_basketball_game_logs enable row level security;
alter table public.historical_mlb_pitches enable row level security;
drop policy if exists "authenticated historical basketball reads" on public.historical_basketball_game_logs;
drop policy if exists "authenticated historical mlb reads" on public.historical_mlb_pitches;
create policy "authenticated historical basketball reads" on public.historical_basketball_game_logs
  for select to authenticated using (true);
create policy "authenticated historical mlb reads" on public.historical_mlb_pitches
  for select to authenticated using (true);
