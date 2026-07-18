create table if not exists public.mlb_umpire_game_assignments (
  game_pk text primary key,
  game_date date not null,
  official_id text not null,
  official_name text not null,
  source text not null,
  raw jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists mlb_umpire_assignment_date_idx
  on public.mlb_umpire_game_assignments(game_date desc, official_id);
alter table public.mlb_umpire_game_assignments enable row level security;
drop policy if exists "authenticated mlb umpire assignment reads" on public.mlb_umpire_game_assignments;
create policy "authenticated mlb umpire assignment reads"
  on public.mlb_umpire_game_assignments for select to authenticated using (true);

alter table public.prediction_snapshots
  add column if not exists snapshot_date date
  generated always as ((created_at at time zone 'UTC')::date) stored;
create unique index if not exists prediction_snapshot_daily_natural_key
  on public.prediction_snapshots(prop_id, model_version, snapshot_date);
create index if not exists prediction_pending_grade_idx
  on public.prediction_snapshots(event_time) where graded_at is null;
