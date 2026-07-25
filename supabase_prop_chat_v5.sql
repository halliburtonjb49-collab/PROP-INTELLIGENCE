-- PROP CHAT v5: apply the same moderation and attachment validation to edits.

begin;

create or replace function public.enforce_prop_chat_message_v4()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  candidate text;
  role_value text;
  active_restriction text;
  blocked_term text;
begin
  if new.user_id <> auth.uid() then
    raise exception 'Messages may only be sent as the authenticated user';
  end if;
  select restriction into active_restriction
  from public.prop_chat_restrictions
  where user_id = new.user_id
    and restriction in ('muted', 'suspended', 'banned')
    and (expires_at is null or expires_at > now());
  if active_restriction is not null then
    raise exception 'Chat access is currently restricted';
  end if;
  select coalesce(nullif(trim(p.username), ''),
           'user_' || left(replace(new.user_id::text, '-', ''), 8)),
         coalesce(u.raw_app_meta_data->>'role', 'user')
    into candidate, role_value
  from auth.users u left join public.user_profiles p on p.id = u.id
  where u.id = new.user_id;
  new.username := left(candidate, 24);
  new.author_role := case when role_value in ('owner', 'admin')
    then role_value else 'user' end;
  new.body := trim(new.body);
  new.link_url := public.validate_prop_chat_link(new.link_url);
  if new.attachment_path is not null and
     new.attachment_path !~ ('^' || new.user_id::text || '/[a-f0-9-]{36}\.(jpg|jpeg|png|webp)$') then
    raise exception 'Invalid attachment path';
  end if;
  select term into blocked_term from public.prop_chat_blocked_terms
  where position(lower(term) in lower(new.body)) > 0 limit 1;
  if blocked_term is not null then
    raise exception 'Message blocked by community safety filter';
  end if;
  if tg_op = 'INSERT' and (select count(*) from public.prop_chat_messages
      where user_id = new.user_id and created_at > now() - interval '60 seconds') >= 12 then
    raise exception 'Message limit reached. Please wait a moment';
  end if;
  if tg_op = 'UPDATE' then new.edited_at := now(); end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_prop_chat_message_v4 on public.prop_chat_messages;
create trigger trg_enforce_prop_chat_message_v4
before insert or update of body, link_url, attachment_path
on public.prop_chat_messages
for each row execute function public.enforce_prop_chat_message_v4();

create or replace function public.enforce_prop_chat_direct_message()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare candidate text; blocked_term text;
begin
  if new.user_id <> auth.uid()
     or not public.is_prop_chat_conversation_member(new.conversation_id) then
    raise exception 'Conversation access denied';
  end if;
  if exists (
    select 1 from public.prop_chat_conversation_members a
    join public.prop_chat_conversation_members b
      on b.conversation_id = a.conversation_id and b.user_id <> a.user_id
    join public.prop_chat_blocks x
      on (x.blocker_id = a.user_id and x.blocked_id = b.user_id)
      or (x.blocker_id = b.user_id and x.blocked_id = a.user_id)
    where a.conversation_id = new.conversation_id and a.user_id = auth.uid()
  ) then raise exception 'Direct messaging is unavailable for this member'; end if;
  select coalesce(nullif(trim(username), ''),
    'user_' || left(replace(new.user_id::text, '-', ''), 8))
  into candidate from public.user_profiles where id = new.user_id;
  new.username := left(coalesce(candidate,
    'user_' || left(replace(new.user_id::text, '-', ''), 8)), 24);
  new.body := trim(new.body);
  new.link_url := public.validate_prop_chat_link(new.link_url);
  if new.attachment_path is not null and
     new.attachment_path !~ ('^' || new.user_id::text || '/[a-f0-9-]{36}\.(jpg|jpeg|png|webp)$') then
    raise exception 'Invalid attachment path';
  end if;
  select term into blocked_term from public.prop_chat_blocked_terms
  where position(lower(term) in lower(new.body)) > 0 limit 1;
  if blocked_term is not null then raise exception 'Message blocked by safety filter'; end if;
  if tg_op = 'INSERT' and (select count(*) from public.prop_chat_direct_messages
      where user_id = new.user_id and created_at > now() - interval '60 seconds') >= 20 then
    raise exception 'Message limit reached. Please wait a moment';
  end if;
  if tg_op = 'UPDATE' then new.edited_at := now(); end if;
  update public.prop_chat_conversations set updated_at = now()
  where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists trg_enforce_prop_chat_direct_message
on public.prop_chat_direct_messages;
create trigger trg_enforce_prop_chat_direct_message
before insert or update of body, link_url, attachment_path
on public.prop_chat_direct_messages
for each row execute function public.enforce_prop_chat_direct_message();

commit;
