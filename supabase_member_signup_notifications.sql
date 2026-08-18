-- Member signup notifications are internal owner-operation records. They are
-- written and read only by the authenticated API, never by browser clients.
create table if not exists public.member_signup_notifications (
  id bigserial primary key,
  user_id text not null unique,
  email text not null default '',
  source text not null default 'app',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  notified_at timestamptz,
  delivery_status text not null default 'pending'
);

create index if not exists member_signup_notifications_first_seen_idx
  on public.member_signup_notifications(first_seen_at desc);

alter table public.member_signup_notifications enable row level security;
alter table public.member_signup_notifications force row level security;
revoke all on public.member_signup_notifications from anon, authenticated;
