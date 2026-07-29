-- Enforce Pro room and structured-analysis access in PostgreSQL.
-- This runs after PROP CHAT v6, which provides required_tier and access helpers.
begin;

alter table public.prop_chat_messages
  add column if not exists message_tier text generated always as (
    case
      when attachment_kind in ('prop', 'slip') or shared_payload is not null
        then 'pro'
      else 'core'
    end
  ) stored;

alter table public.prop_chat_direct_messages
  add column if not exists message_tier text generated always as (
    case
      when attachment_kind in ('prop', 'slip') or shared_payload is not null
        then 'pro'
      else 'core'
    end
  ) stored;

drop policy if exists prop_chat_rooms_read on public.prop_chat_rooms;
create policy prop_chat_rooms_read on public.prop_chat_rooms
for select to authenticated using (
  public.can_access_prop_chat_room(id) or public.is_prop_chat_moderator()
);

drop policy if exists prop_chat_messages_read on public.prop_chat_messages;
create policy prop_chat_messages_read on public.prop_chat_messages
for select to authenticated using (
  public.can_access_prop_chat_room(room_id)
  and (message_tier = 'core' or public.prop_chat_access_level() >= 2)
  and (deleted_at is null or public.is_prop_chat_moderator())
);

drop policy if exists prop_chat_messages_send on public.prop_chat_messages;
create policy prop_chat_messages_send on public.prop_chat_messages
for insert to authenticated with check (
  auth.uid() = user_id
  and public.can_access_prop_chat_room(room_id)
  and (message_tier = 'core' or public.prop_chat_access_level() >= 2)
);

drop policy if exists prop_chat_direct_messages_read
  on public.prop_chat_direct_messages;
create policy prop_chat_direct_messages_read
on public.prop_chat_direct_messages
for select to authenticated using (
  public.prop_chat_access_level() >= 1
  and public.is_prop_chat_conversation_member(conversation_id)
  and (message_tier = 'core' or public.prop_chat_access_level() >= 2)
);

drop policy if exists prop_chat_direct_messages_send
  on public.prop_chat_direct_messages;
create policy prop_chat_direct_messages_send
on public.prop_chat_direct_messages
for insert to authenticated with check (
  public.prop_chat_access_level() >= 1
  and user_id = auth.uid()
  and public.is_prop_chat_conversation_member(conversation_id)
  and (message_tier = 'core' or public.prop_chat_access_level() >= 2)
);

commit;
