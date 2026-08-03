create table if not exists public.historical_odds_backfill_jobs (
    id bigserial primary key,
    sport text not null,
    event_id text not null,
    markets text[] not null,
    regions text[] not null,
    requested_at timestamptz not null,
    snapshot_at timestamptz,
    previous_snapshot_at timestamptz,
    next_snapshot_at timestamptz,
    status text not null check (status in ('PENDING', 'SUCCEEDED', 'EMPTY', 'FAILED')),
    estimated_credits integer not null default 0,
    consumed_credits integer,
    quota_remaining integer,
    error text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (sport, event_id, markets, regions, requested_at)
);

create index if not exists historical_odds_backfill_lookup_idx
    on public.historical_odds_backfill_jobs
    (sport, event_id, requested_at);

alter table public.historical_odds_backfill_jobs enable row level security;
revoke all on table public.historical_odds_backfill_jobs from anon, authenticated;
revoke all on sequence public.historical_odds_backfill_jobs_id_seq from anon, authenticated;

