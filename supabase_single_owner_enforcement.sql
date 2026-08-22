-- Permanently bind owner authorization to the one verified PI account.
-- Metadata, subscription status, and environment variables cannot create a
-- second owner.
begin;

delete from public.app_owner_accounts
where user_id <> '84a76503-f704-46b6-be87-760ea8c9f2f5'::uuid;

insert into public.app_owner_accounts (user_id)
values ('84a76503-f704-46b6-be87-760ea8c9f2f5'::uuid)
on conflict (user_id) do nothing;

update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'role'
where id <> '84a76503-f704-46b6-be87-760ea8c9f2f5'::uuid
  and coalesce(raw_app_meta_data->>'role', '') = 'owner';

update auth.users
set raw_app_meta_data =
  coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'owner')
where id = '84a76503-f704-46b6-be87-760ea8c9f2f5'::uuid;

drop policy if exists "owners can read role audit"
on public.role_assignment_audit;
create policy "owners can read role audit"
on public.role_assignment_audit
for select to authenticated
using (public.is_app_owner(auth.uid()));

create or replace function public.assign_user_role(
  target_email text,
  target_role text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text := lower(trim(target_email));
  normalized_role text := lower(trim(target_role));
  target_record auth.users%rowtype;
  previous_role text;
begin
  if not public.is_app_owner(auth.uid()) then
    raise exception 'Only the verified owner can assign roles.' using errcode = '42501';
  end if;

  if normalized_role not in ('admin', 'tester', 'user') then
    raise exception 'Role must be admin, tester, or user.' using errcode = '22023';
  end if;

  select * into target_record
  from auth.users
  where lower(email) = normalized_email
  limit 1;

  if target_record.id is null then
    raise exception 'No registered user exists for that email.' using errcode = 'P0002';
  end if;
  if public.is_app_owner(target_record.id) then
    raise exception 'The owner account cannot be changed here.' using errcode = '42501';
  end if;

  previous_role := coalesce(target_record.raw_app_meta_data->>'role', 'user');
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
    || jsonb_build_object('role', normalized_role)
  where id = target_record.id;

  insert into public.role_assignment_audit (
    assigned_by, target_user_id, target_email, previous_role, new_role
  ) values (
    auth.uid(), target_record.id, normalized_email, previous_role, normalized_role
  );

  return jsonb_build_object(
    'email', normalized_email,
    'previous_role', previous_role,
    'role', normalized_role
  );
end;
$$;

create or replace function public.is_prop_chat_moderator()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select public.is_app_owner(auth.uid())
    or coalesce(auth.jwt()->'app_metadata'->>'role', '') = 'admin';
$$;

commit;
