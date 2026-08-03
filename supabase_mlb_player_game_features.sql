create table if not exists public.mlb_player_game_features (
  id text primary key,
  player_role text not null check (player_role in ('BATTER','PITCHER')),
  player_id text not null,
  game_pk text not null,
  game_date date not null,
  outcomes jsonb not null default '{}'::jsonb,
  pregame_features jsonb not null default '{}'::jsonb,
  prior_dates integer not null default 0 check (prior_dates >= 0),
  feature_version text not null,
  source text not null default 'baseball-savant-statcast',
  updated_at timestamptz not null default now(),
  unique(player_role, player_id, game_pk, feature_version)
);

create index if not exists mlb_player_features_lookup_idx
  on public.mlb_player_game_features(player_role, player_id, game_date desc);
create index if not exists mlb_player_features_version_idx
  on public.mlb_player_game_features(feature_version, game_date desc);

alter table public.mlb_player_game_features enable row level security;
revoke all on public.mlb_player_game_features from anon, authenticated;
