-- Closed-loop prop learning: long-horizon snapshots, graded results, and model metrics.
create table if not exists public.prop_prediction_snapshots (
  id uuid primary key default gen_random_uuid(),
  prop_id text not null,
  player_id text not null,
  sport text not null,
  market text not null,
  side text not null check (side in ('OVER', 'UNDER')),
  line double precision not null,
  projection double precision,
  hit_probability double precision,
  model_version text not null,
  source_provider text not null,
  sportsbook text not null,
  event_time timestamptz,
  snapshot_date date not null default (now() at time zone 'UTC')::date,
  created_at timestamptz not null default now(),
  inputs jsonb not null default '{}'::jsonb
);
create unique index if not exists prop_learning_snapshot_daily_key
  on public.prop_prediction_snapshots(
    snapshot_date, prop_id, model_version, source_provider, sportsbook, line, side
  );
create index if not exists prop_learning_snapshot_event_idx
  on public.prop_prediction_snapshots(event_time, sport, market, model_version);

create table if not exists public.prop_results (
  id uuid primary key default gen_random_uuid(),
  prop_prediction_snapshot_id uuid not null references public.prop_prediction_snapshots(id) on delete cascade,
  grade_state text not null
    check (grade_state in ('PENDING', 'WIN', 'LOSS', 'PUSH', 'VOID', 'ERROR')),
  actual_value double precision,
  hit boolean,
  result_source text,
  grade_reason text,
  graded_at timestamptz,
  result_inputs jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (prop_prediction_snapshot_id)
);
create index if not exists prop_results_state_idx
  on public.prop_results(grade_state, created_at desc);
create index if not exists prop_results_snapshot_idx
  on public.prop_results(prop_prediction_snapshot_id);

create table if not exists public.model_performance_metrics (
  id uuid primary key default gen_random_uuid(),
  metric_date date not null default (now() at time zone 'UTC')::date,
  model_version text not null,
  sport text not null,
  market text not null,
  sample_size integer not null default 0,
  win_count integer not null default 0,
  loss_count integer not null default 0,
  push_count integer not null default 0,
  void_count integer not null default 0,
  pending_count integer not null default 0,
  win_rate double precision,
  push_rate double precision,
  computed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (metric_date, model_version, sport, market)
);
create index if not exists model_performance_metrics_idx
  on public.model_performance_metrics(metric_date desc, model_version, sport, market);

alter table public.prop_prediction_snapshots enable row level security;
alter table public.prop_prediction_snapshots force row level security;
alter table public.prop_results enable row level security;
alter table public.prop_results force row level security;
alter table public.model_performance_metrics enable row level security;
alter table public.model_performance_metrics force row level security;

revoke all on public.prop_prediction_snapshots from anon, authenticated;
revoke all on public.prop_results from anon, authenticated;
revoke all on public.model_performance_metrics from anon, authenticated;

create policy "owner prop_learning_snapshot reads" on public.prop_prediction_snapshots
  for all to authenticated
  using (public.is_app_owner(auth.uid()))
  with check (public.is_app_owner(auth.uid()));
create policy "owner prop_learning_results reads" on public.prop_results
  for all to authenticated
  using (public.is_app_owner(auth.uid()))
  with check (public.is_app_owner(auth.uid()));
create policy "owner prop_learning_metrics reads" on public.model_performance_metrics
  for all to authenticated
  using (public.is_app_owner(auth.uid()))
  with check (public.is_app_owner(auth.uid()));
