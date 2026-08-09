-- User feedback is accepted and reviewed exclusively through authenticated API
-- routes. Keep the backing records inaccessible through Supabase/PostgREST.
create table if not exists public.user_feedback_messages (
  id bigserial primary key,
  user_id text not null,
  category text not null,
  message text not null,
  page text not null default '',
  status text not null default 'new',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text
);

create index if not exists user_feedback_messages_created_idx
  on public.user_feedback_messages(created_at desc);
create index if not exists user_feedback_messages_status_idx
  on public.user_feedback_messages(status);

alter table public.user_feedback_messages enable row level security;
alter table public.user_feedback_messages force row level security;
revoke all on public.user_feedback_messages from anon, authenticated;
