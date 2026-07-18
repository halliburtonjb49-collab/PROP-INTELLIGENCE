create table if not exists public.pipeline_runs (
  id uuid primary key default gen_random_uuid(),
  pipeline text not null,
  status text not null check (status in ('RUNNING','SUCCEEDED','PARTIAL','FAILED')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  duration_ms bigint,
  metrics jsonb not null default '{}'::jsonb,
  errors jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists pipeline_runs_recent_idx
  on public.pipeline_runs(pipeline, started_at desc);
alter table public.pipeline_runs enable row level security;
drop policy if exists "authenticated pipeline run reads" on public.pipeline_runs;
create policy "authenticated pipeline run reads"
  on public.pipeline_runs for select to authenticated using (true);
