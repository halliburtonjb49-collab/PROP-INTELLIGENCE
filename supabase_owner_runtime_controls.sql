-- Owner-managed runtime controls (release gates, thresholds) read by the API.
-- Internal operations state only; never queried by the browser.
--
-- The service created this table lazily at runtime, which left it without row
-- level security and failed the pre-deploy guard on every deployment. Declaring
-- it here brings it under the same protection as every other internal table;
-- the runtime path now only ensures it exists.
create table if not exists public.owner_runtime_controls (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.owner_runtime_controls enable row level security;
alter table public.owner_runtime_controls force row level security;
revoke all on public.owner_runtime_controls from anon, authenticated;
