-- Repair runtime grants required by PROP CHAT RLS policies and RPCs. These
-- functions are SECURITY DEFINER and validate auth.uid()/owner access inside
-- their bodies; authenticated members need EXECUTE for policy evaluation.

begin;

grant execute on function public.is_app_owner(uuid) to authenticated;
grant execute on function public.is_prop_chat_moderator() to authenticated;
grant execute on function public.can_access_prop_chat_room(text) to authenticated;
grant execute on function public.prop_chat_access_level() to authenticated;
grant execute on function public.prop_chat_notification_summary() to authenticated;
grant execute on function public.prop_chat_unread_summary() to authenticated;
grant execute on function public.latest_prop_chat_announcement() to authenticated;
grant execute on function public.publish_prop_chat_announcement(text) to authenticated;

do $$
declare
  signature text;
begin
  foreach signature in array array[
    'public.is_app_owner(uuid)',
    'public.is_prop_chat_moderator()',
    'public.can_access_prop_chat_room(text)',
    'public.prop_chat_access_level()',
    'public.prop_chat_notification_summary()',
    'public.prop_chat_unread_summary()',
    'public.latest_prop_chat_announcement()',
    'public.publish_prop_chat_announcement(text)'
  ]
  loop
    if not has_function_privilege('authenticated', signature, 'EXECUTE') then
      raise exception 'Missing authenticated EXECUTE grant for %', signature;
    end if;
  end loop;
end
$$;

commit;
