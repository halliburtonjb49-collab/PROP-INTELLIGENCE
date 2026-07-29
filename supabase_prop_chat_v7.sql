-- PROP CHAT v7: persistent notification counts for public mentions and
-- participant-only direct messages.

begin;

create or replace function public.prop_chat_notification_summary()
returns table(
  notification_type text,
  source_id text,
  unread_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    'mention'::text,
    r.id::text,
    count(m.id)::bigint
  from public.prop_chat_rooms r
  join public.user_profiles profile on profile.id = auth.uid()
  left join public.prop_chat_read_state state
    on state.room_id = r.id and state.user_id = auth.uid()
  left join public.prop_chat_messages m
    on m.room_id = r.id
    and m.user_id <> auth.uid()
    and m.created_at > coalesce(state.last_read_at, 'epoch'::timestamptz)
    and m.deleted_at is null
    and lower(m.body) ~ (
      '(^|[^a-z0-9_])@'
      || lower(profile.username)
      || '([^a-z0-9_]|$)'
    )
  where r.is_active
    and profile.username is not null
  group by r.id

  union all

  select
    'direct'::text,
    membership.conversation_id::text,
    count(message.id)::bigint
  from public.prop_chat_conversation_members membership
  left join public.prop_chat_direct_messages message
    on message.conversation_id = membership.conversation_id
    and message.user_id <> auth.uid()
    and message.created_at > membership.last_read_at
    and message.deleted_at is null
  where membership.user_id = auth.uid()
  group by membership.conversation_id;
$$;

revoke all on function public.prop_chat_notification_summary() from public;
grant execute on function public.prop_chat_notification_summary()
  to authenticated;

commit;
