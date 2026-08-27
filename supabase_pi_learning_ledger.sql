-- Immutable audit history for every PI adaptive-learning decision.
create table if not exists public.pi_learning_ledger (
  id uuid primary key default gen_random_uuid(),
  decision_key text not null unique,
  model_version text not null,
  status text not null check (status in ('PROMOTED', 'DEVELOPING', 'REJECTED')),
  sport text not null,
  market text not null,
  dimension text not null,
  segment_label text not null,
  sample_size integer not null,
  wins integer not null,
  losses integer not null,
  baseline_rate double precision,
  observed_rate double precision,
  lift double precision,
  evidence jsonb not null default '{}'::jsonb,
  explanation text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists pi_learning_ledger_recent_idx
  on public.pi_learning_ledger(created_at desc, model_version, status);

create or replace function public.protect_pi_learning_ledger()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'PI learning history is append-only';
end;
$$;

revoke all on function public.protect_pi_learning_ledger() from public, anon, authenticated;
drop trigger if exists pi_learning_ledger_append_only on public.pi_learning_ledger;
create trigger pi_learning_ledger_append_only
before update or delete on public.pi_learning_ledger
for each row execute function public.protect_pi_learning_ledger();

alter table public.pi_learning_ledger enable row level security;
alter table public.pi_learning_ledger force row level security;
revoke all on public.pi_learning_ledger from anon, authenticated;
create policy "owner pi learning ledger reads" on public.pi_learning_ledger
  for select to authenticated using (public.is_app_owner(auth.uid()));
