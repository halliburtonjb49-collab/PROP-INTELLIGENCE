-- Support the latest-observation DISTINCT ON lookup used for prop enrichment.
-- This is a forward-only migration because the base table migration is already
-- deployed and protected by its recorded checksum.
create index if not exists pregame_context_latest_lookup_idx
  on public.pregame_context_observations (
    provider,
    entity_type,
    event_id,
    lower(player_name),
    observed_at desc
  );
