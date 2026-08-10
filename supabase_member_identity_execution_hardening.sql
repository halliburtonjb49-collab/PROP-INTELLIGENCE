-- Explicitly remove Supabase anon execution from member identity functions.
-- Separate because supabase_member_identity_roles.sql is immutable once applied.
begin;

revoke all on function public.assign_member_identity_role(text, text, integer)
  from public, anon, authenticated;
grant execute on function public.assign_member_identity_role(text, text, integer)
  to authenticated;

revoke all on function public.prevent_member_access_self_assignment()
  from public, anon, authenticated;

commit;
