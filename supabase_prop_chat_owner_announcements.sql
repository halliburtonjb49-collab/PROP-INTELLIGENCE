-- Secure owner-wide announcements and retain the normal member message limit.

begin;

create or replace function public.enforce_prop_chat_message_length_and_announcement()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  owner_message boolean := public.is_app_owner(new.user_id);
begin
  if left(new.body, 18) = E'[PI ANNOUNCEMENT]\n' and not owner_message then
    raise exception 'Only the owner can publish announcements';
  end if;

  if char_length(new.body) > 500 and not owner_message then
    raise exception 'Messages must contain 1-500 characters';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prop_chat_owner_announcement_guard
on public.prop_chat_messages;
create trigger trg_prop_chat_owner_announcement_guard
before insert or update of body on public.prop_chat_messages
for each row execute function public.enforce_prop_chat_message_length_and_announcement();

commit;
