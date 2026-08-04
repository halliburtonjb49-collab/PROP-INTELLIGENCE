-- Durable last-known-good prop catalog shared by the API and worker.
-- Internal recovery cache only; never queried by the browser.
create table if not exists public.prop_catalog_snapshots (
  snapshot_key text primary key,
  payload bytea not null,
  prop_count integer not null,
  data_updated_at text,
  updated_at timestamptz not null default now()
);

alter table public.prop_catalog_snapshots enable row level security;
alter table public.prop_catalog_snapshots force row level security;
revoke all on public.prop_catalog_snapshots from anon, authenticated;
