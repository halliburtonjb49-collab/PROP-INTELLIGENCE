-- One durable, service-readable snapshot of the latest pregame provider run.
-- Redis remains the fast path; PostgreSQL prevents worker/API cache divergence
-- from making Owner Ops report that no availability sync has ever run.

create table if not exists public.provider_availability_snapshots (
  id boolean primary key default true check (id),
  generated_at timestamptz not null,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.provider_availability_snapshots enable row level security;
revoke all on table public.provider_availability_snapshots from anon, authenticated;

