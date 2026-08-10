-- Restrict SECURITY DEFINER functions to the smallest practical caller set.
-- PostgreSQL grants EXECUTE to PUBLIC by default, which also exposes functions
-- to Supabase's anon and authenticated API roles unless it is revoked.

begin;

alter function public.validate_prop_chat_link(text)
  set search_path = pg_catalog;

alter default privileges revoke execute on functions from public;

do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated',
      fn.signature
    );
    execute format(
      'grant execute on function %s to service_role',
      fn.signature
    );
  end loop;
end
$$;

-- These functions are deliberately callable by signed-in users. Each one
-- either scopes its operation to auth.uid(), enforces an owner/moderator role,
-- or is required by an RLS policy. Trigger and maintenance functions are
-- intentionally absent so they cannot be invoked through PostgREST RPC.
do $$
declare
  signature text;
  fn regprocedure;
begin
  foreach signature in array array[
    'public.acknowledge_prop_chat_notice(bigint)',
    'public.assign_user_role(text,text)',
    'public.can_access_prop_chat_room(text)',
    'public.create_prop_chat_game_thread(text,text,text)',
    'public.effective_account_role()',
    'public.find_prop_chat_members(text)',
    'public.is_app_owner(uuid)',
    'public.is_prop_chat_conversation_member(uuid)',
    'public.is_prop_chat_moderator()',
    'public.list_app_change_requests()',
    'public.prop_chat_access_level()',
    'public.prop_chat_direct_conversations()',
    'public.prop_chat_health()',
    'public.prop_chat_notification_summary()',
    'public.prop_chat_unread_summary()',
    'public.review_app_change_request(bigint,text,text)',
    'public.set_prop_chat_member_role(uuid,text,boolean)',
    'public.set_prop_chat_public_username(text)',
    'public.start_prop_chat_direct_conversation(uuid)',
    'public.submit_app_change_request(text,text)'
  ]
  loop
    fn := to_regprocedure(signature);
    if fn is not null then
      execute format('grant execute on function %s to authenticated', fn);
    end if;
  end loop;
end
$$;

commit;
