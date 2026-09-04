-- Make owner announcements a first-class global channel instead of relying on
-- the selected room's RLS policy. Publishing remains owner-only; reading is
-- available to every authenticated member.

begin;

create or replace function public.publish_prop_chat_announcement(message_body text)
returns bigint
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  message_id bigint;
  normalized_body text := trim(coalesce(message_body, ''));
begin
  if auth.uid() is null then
    raise exception 'Sign in to publish announcements';
  end if;
  if not public.is_app_owner(auth.uid()) then
    raise exception 'Only the owner can publish announcements';
  end if;
  if normalized_body = '' then
    raise exception 'Enter an announcement before publishing';
  end if;

  insert into public.prop_chat_messages (
    user_id, username, body, room_id, link_url
  ) values (
    auth.uid(),
    'server-assigned',
    E'[PI ANNOUNCEMENT]\n' || normalized_body,
    'general',
    case
      when normalized_body ~ 'https://[^[:space:]]+'
        then substring(normalized_body from 'https://[^[:space:]]+')
      else null
    end
  ) returning id into message_id;

  return message_id;
end;
$$;

revoke all on function public.publish_prop_chat_announcement(text) from public, anon;
grant execute on function public.publish_prop_chat_announcement(text) to authenticated;

create or replace function public.latest_prop_chat_announcement()
returns setof public.prop_chat_messages
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to read announcements';
  end if;
  return query
    select message.*
    from public.prop_chat_messages message
    where message.room_id = 'general'
      and message.body like E'[PI ANNOUNCEMENT]\n%'
      and message.deleted_at is null
    order by message.created_at desc
    limit 1;
end;
$$;

revoke all on function public.latest_prop_chat_announcement() from public, anon;
grant execute on function public.latest_prop_chat_announcement() to authenticated;

commit;
