create table if not exists public.matchup_feature_snapshots (
  id uuid primary key default gen_random_uuid(),
  prediction_snapshot_id uuid references public.prediction_snapshots(id) on delete cascade,
  prop_id text not null,
  player_id text not null,
  sport text not null,
  market text not null,
  event_time timestamptz not null,
  captured_at timestamptz not null default now(),
  features jsonb not null default '{}'::jsonb,
  source_versions jsonb not null default '{}'::jsonb,
  unique(prediction_snapshot_id)
);

create table if not exists public.paper_trade_entries (
  id uuid primary key default gen_random_uuid(),
  prediction_snapshot_id uuid not null unique references public.prediction_snapshots(id) on delete cascade,
  prop_id text not null,
  player_id text not null,
  sport text not null,
  market text not null,
  side text not null check (side in ('OVER','UNDER')),
  grade text not null check (grade in ('A','B')),
  line double precision not null,
  projection double precision not null,
  confidence double precision not null,
  model_version text not null,
  sportsbook text not null default '',
  event_time timestamptz not null,
  locked_at timestamptz not null default now(),
  decision_inputs jsonb not null default '{}'::jsonb
);

create table if not exists public.paper_trade_results (
  paper_trade_id uuid primary key references public.paper_trade_entries(id) on delete cascade,
  actual_value double precision not null,
  hit boolean not null,
  closing_line double precision,
  closing_no_vig_probability double precision,
  odds_clv_expected_value_percent double precision,
  graded_at timestamptz not null,
  result_source text not null default ''
);

create table if not exists public.model_challenger_evaluations (
  id uuid primary key default gen_random_uuid(),
  model_version text not null,
  baseline_version text not null,
  sport text not null,
  market text not null,
  training_start date not null,
  training_end date not null,
  validation_start date not null,
  validation_end date not null,
  sample_size integer not null,
  metrics jsonb not null,
  baseline_metrics jsonb not null,
  promoted boolean not null default false,
  evaluated_at timestamptz not null default now()
);

create index if not exists matchup_feature_segment_idx
  on public.matchup_feature_snapshots(sport,market,event_time desc);
create index if not exists paper_trade_segment_idx
  on public.paper_trade_entries(sport,market,side,grade,event_time desc);
create index if not exists challenger_segment_idx
  on public.model_challenger_evaluations(sport,market,evaluated_at desc);

create or replace function public.prevent_paper_trade_entry_update()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception 'Paper-trade entries are immutable after capture';
end;
$$;
drop trigger if exists paper_trade_entries_immutable
  on public.paper_trade_entries;
create trigger paper_trade_entries_immutable
before update on public.paper_trade_entries
for each row execute function public.prevent_paper_trade_entry_update();

alter table public.matchup_feature_snapshots enable row level security;
alter table public.paper_trade_entries enable row level security;
alter table public.paper_trade_results enable row level security;
alter table public.model_challenger_evaluations enable row level security;
revoke all on public.matchup_feature_snapshots from anon, authenticated;
revoke all on public.paper_trade_entries from anon, authenticated;
revoke all on public.paper_trade_results from anon, authenticated;
revoke all on public.model_challenger_evaluations from anon, authenticated;
revoke all on function public.prevent_paper_trade_entry_update() from public;
