-- Sport must lead the DISTINCT ON key because ESPN event ids are report dates
-- shared by NBA, WNBA, NHL and NFL. Without it, one league suppresses another.
create index if not exists pregame_context_sport_latest_lookup_idx
  on public.pregame_context_observations (
    sport,
    provider,
    entity_type,
    event_id,
    lower(player_name),
    observed_at desc
  );