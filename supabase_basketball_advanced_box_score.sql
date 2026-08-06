-- Shooting and rebounding detail needed for usage, shot-attempt rates and a
-- beta-binomial three-point percentage.
--
-- These values were already being captured: the ingestion stores the entire
-- provider box-score row in `raw`, so the history is present but unqueryable
-- without a jsonb extraction on every read. Promoting them to typed columns
-- and backfilling from `raw` makes the existing seasons usable immediately,
-- with no re-ingestion and no provider calls.
alter table public.historical_basketball_game_logs
  add column if not exists field_goals_made double precision,
  add column if not exists field_goals_attempted double precision,
  add column if not exists three_point_attempts double precision,
  add column if not exists free_throws_made double precision,
  add column if not exists offensive_rebounds double precision,
  add column if not exists defensive_rebounds double precision;

update public.historical_basketball_game_logs
set
  field_goals_made = coalesce(
    field_goals_made, nullif(raw->>'FGM', '')::double precision
  ),
  field_goals_attempted = coalesce(
    field_goals_attempted, nullif(raw->>'FGA', '')::double precision
  ),
  three_point_attempts = coalesce(
    three_point_attempts, nullif(raw->>'FG3A', '')::double precision
  ),
  free_throws_made = coalesce(
    free_throws_made, nullif(raw->>'FTM', '')::double precision
  ),
  offensive_rebounds = coalesce(
    offensive_rebounds, nullif(raw->>'OREB', '')::double precision
  ),
  defensive_rebounds = coalesce(
    defensive_rebounds, nullif(raw->>'DREB', '')::double precision
  )
where raw ? 'FGA' and field_goals_attempted is null;

-- Usage and pace are computed per team-game, which reads every player in a
-- game together rather than one player across games.
create index if not exists basketball_team_game_idx
  on public.historical_basketball_game_logs(sport, league_game_id, team_id);
