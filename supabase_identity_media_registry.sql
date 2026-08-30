create extension if not exists pgcrypto;

create table if not exists public.pi_identities (
  id uuid primary key default gen_random_uuid(), identity_type text not null check (identity_type in ('player','team')),
  sport text not null, canonical_name text not null, normalized_name text not null,
  status text not null default 'active' check (status in ('active','unmatched','merged','retired')),
  metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), unique(identity_type, sport, normalized_name)
);
create table if not exists public.pi_identity_aliases (
  id bigint generated always as identity primary key, pi_identity_id uuid not null references public.pi_identities(id) on delete cascade,
  provider text not null, provider_identity_id text not null default '', alias text not null,
  normalized_alias text not null, abbreviation text not null default '', confidence numeric(5,4) not null default 1,
  last_seen_at timestamptz not null default now(), metadata jsonb not null default '{}'::jsonb,
  unique(provider, provider_identity_id, normalized_alias)
);
create index if not exists pi_identity_alias_lookup_idx on public.pi_identity_aliases(provider, normalized_alias);
create table if not exists public.pi_identity_media (
  id bigint generated always as identity primary key, pi_identity_id uuid not null references public.pi_identities(id) on delete cascade,
  media_type text not null check (media_type in ('headshot','logo')), source_provider text not null,
  source_url text not null, cached_url text not null default '', content_hash text not null default '',
  status text not null default 'candidate' check (status in ('candidate','approved','failed','retired')),
  is_last_known_good boolean not null default false, last_verified_at timestamptz, last_failed_at timestamptz,
  failure_count integer not null default 0, metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(pi_identity_id, media_type, source_provider, source_url)
);
create unique index if not exists pi_identity_media_one_lkg_idx on public.pi_identity_media(pi_identity_id, media_type) where is_last_known_good;
create table if not exists public.pi_identity_reconciliation_queue (
  id bigint generated always as identity primary key, identity_type text not null check (identity_type in ('player','team','prop')),
  sport text not null default 'UNKNOWN', provider text not null, provider_identity_id text not null default '',
  observed_name text not null default '', normalized_name text not null default '', reason text not null,
  sample_payload jsonb not null default '{}'::jsonb, occurrence_count integer not null default 1,
  first_seen_at timestamptz not null default now(), last_seen_at timestamptz not null default now(), resolved_at timestamptz,
  resolved_pi_identity_id uuid references public.pi_identities(id),
  unique(identity_type, sport, provider, provider_identity_id, normalized_name, reason)
);
create index if not exists pi_identity_queue_open_idx on public.pi_identity_reconciliation_queue(last_seen_at desc) where resolved_at is null;
create table if not exists public.pi_provider_inventory_observations (
  id bigint generated always as identity primary key, provider text not null, sport text not null,
  prop_count integer not null, prior_prop_count integer, change_ratio numeric(8,5),
  status text not null check (status in ('healthy','warning','critical','interrupted')),
  observed_at timestamptz not null default now(), metadata jsonb not null default '{}'::jsonb
);
create index if not exists pi_provider_inventory_recent_idx on public.pi_provider_inventory_observations(provider, sport, observed_at desc);
alter table public.pi_identities enable row level security;
alter table public.pi_identity_aliases enable row level security;
alter table public.pi_identity_media enable row level security;
alter table public.pi_identity_reconciliation_queue enable row level security;
alter table public.pi_provider_inventory_observations enable row level security;
revoke all on public.pi_identities from anon, authenticated;
revoke all on public.pi_identity_aliases from anon, authenticated;
revoke all on public.pi_identity_media from anon, authenticated;
revoke all on public.pi_identity_reconciliation_queue from anon, authenticated;
revoke all on public.pi_provider_inventory_observations from anon, authenticated;

