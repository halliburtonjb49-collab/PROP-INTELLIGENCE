create table if not exists public.basketball_defender_matchups (
  sport text not null,
  season text not null,
  offensive_player_id text not null,
  offensive_player_name text not null,
  defensive_player_id text not null,
  defensive_player_name text not null,
  matchup_minutes double precision not null default 0,
  partial_possessions double precision not null default 0,
  player_points double precision not null default 0,
  matchup_fga double precision not null default 0,
  matchup_fg_pct double precision,
  games integer not null default 0,
  source text not null,
  updated_at timestamptz not null default now(),
  primary key(sport,season,offensive_player_id,defensive_player_id)
);

create index if not exists defender_matchup_offense_idx
  on public.basketball_defender_matchups(sport,season,offensive_player_id,partial_possessions desc);

alter table public.basketball_defender_matchups enable row level security;
revoke all on public.basketball_defender_matchups from anon, authenticated;
