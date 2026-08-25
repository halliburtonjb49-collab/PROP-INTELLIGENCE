-- Repair production Prop Chat schema drift and make its realtime publication
-- idempotent. Safe to run repeatedly.
begin;

alter table public.prop_chat_rooms
  add column if not exists room_type text not null default 'sport',
  add column if not exists sport text,
  add column if not exists event_id text,
  add column if not exists required_tier text not null default 'core';

update public.prop_chat_rooms
set room_type = 'general', required_tier = 'core'
where id = 'general';

alter table public.prop_chat_messages
  add column if not exists reply_to_id bigint references public.prop_chat_messages(id) on delete set null,
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists author_role text not null default 'user',
  add column if not exists author_badge_number integer,
  add column if not exists attachment_path text,
  add column if not exists attachment_kind text,
  add column if not exists link_url text,
  add column if not exists shared_payload jsonb;

create index if not exists idx_prop_chat_messages_room_created
  on public.prop_chat_messages(room_id, created_at desc);

create unique index if not exists prop_chat_rooms_event_id_unique
  on public.prop_chat_rooms(event_id) where event_id is not null;

alter table public.prop_chat_presence enable row level security;

drop policy if exists prop_chat_presence_read on public.prop_chat_presence;
create policy prop_chat_presence_read on public.prop_chat_presence
for select to authenticated
using (last_seen_at > now() - interval '2 minutes');

drop policy if exists prop_chat_presence_own on public.prop_chat_presence;
create policy prop_chat_presence_own on public.prop_chat_presence
for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists prop_chat_presence_update on public.prop_chat_presence;
create policy prop_chat_presence_update on public.prop_chat_presence
for update to authenticated
using (auth.uid() = user_id) with check (auth.uid() = user_id);

do $$
begin
  alter publication supabase_realtime add table public.prop_chat_messages;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.prop_chat_reactions;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.prop_chat_presence;
exception when duplicate_object then null;
end $$;

commit;
