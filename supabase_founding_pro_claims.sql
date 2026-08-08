begin;

create table if not exists public.founding_pro_claims (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null check (status in ('reserved', 'active', 'released')),
  reserved_at timestamptz,
  reservation_expires_at timestamptz,
  claimed_at timestamptz,
  released_at timestamptz,
  product_id text,
  updated_at timestamptz not null default now(),
  check (
    (status = 'reserved' and reserved_at is not null and reservation_expires_at is not null and claimed_at is null)
    or (status = 'active' and claimed_at is not null and released_at is null)
    or (status = 'released' and claimed_at is not null and released_at is not null)
  )
);

create index if not exists founding_pro_claims_capacity_idx
  on public.founding_pro_claims(status, reservation_expires_at, claimed_at);

alter table public.founding_pro_claims enable row level security;
alter table public.founding_pro_claims force row level security;
revoke all on public.founding_pro_claims from anon, authenticated;

commit;
