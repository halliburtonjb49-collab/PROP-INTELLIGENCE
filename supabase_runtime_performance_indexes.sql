-- Production request and settlement indexes. All statements are idempotent.
create index if not exists prop_catalog_snapshots_updated_idx
  on public.prop_catalog_snapshots(updated_at desc)
  where prop_count > 0;

create index if not exists prop_prediction_pending_event_idx
  on public.prop_prediction_snapshots(event_time, sport, market, player_id)
  where event_time is not null;

create index if not exists prop_results_pending_grade_idx
  on public.prop_results(created_at, prop_prediction_snapshot_id)
  where grade_state = 'PENDING';

create index if not exists sportsbook_provider_market_time_idx
  on public.sportsbook_line_snapshots(provider, sport, market, observed_at desc);

create index if not exists slips_user_created_idx
  on public.slips(user_id, created_at desc);

create index if not exists pipeline_runs_unfinished_idx
  on public.pipeline_runs(started_at)
  where finished_at is null;
