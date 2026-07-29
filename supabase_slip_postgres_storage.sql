begin;

create table if not exists public.slips (
  id text primary key,
  user_id text,
  status text not null check (status in ('active', 'won', 'lost')),
  stake double precision not null check (stake >= 0),
  potential_payout double precision not null check (potential_payout >= 0),
  created_at timestamptz not null,
  legs_json jsonb not null
);

create index if not exists slips_user_status_idx
  on public.slips(user_id, status, created_at desc);

alter table public.slips enable row level security;
alter table public.slips force row level security;
revoke all on public.slips from anon, authenticated;

commit;
