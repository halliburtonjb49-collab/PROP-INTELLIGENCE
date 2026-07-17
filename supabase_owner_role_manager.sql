-- Run once in Supabase SQL Editor.
-- Owners can assign admin, tester, or user roles without exposing service keys.

create table if not exists public.role_assignment_audit (
  id bigint generated always as identity primary key,
  assigned_by uuid not null,
  target_user_id uuid not null,
  target_email text not null,
  previous_role text not null,
  new_role text not null,
  created_at timestamptz not null default now()
);

alter table public.role_assignment_audit enable row level security;

drop policy if exists "owners can read role audit" on public.role_assignment_audit;
create policy "owners can read role audit"
on public.role_assignment_audit
for select
to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'owner');

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
  requester_role text := coalesce(
    auth.jwt() -> 'app_metadata' ->> 'role',
    'user'
  );
  normalized_email text := lower(trim(target_email));
  normalized_role text := lower(trim(target_role));
  target_record auth.users%rowtype;
  previous_role text;
begin
  if requester_role <> 'owner' then
    raise exception 'Only an owner can assign roles.' using errcode = '42501';
  end if;

  if normalized_role not in ('admin', 'tester', 'user') then
    raise exception 'Role must be admin, tester, or user.' using errcode = '22023';
  end if;

  select *
  into target_record
  from auth.users
  where lower(email) = normalized_email
  limit 1;

  if target_record.id is null then
    raise exception 'No registered user exists for that email.' using errcode = 'P0002';
  end if;

  previous_role := coalesce(
    target_record.raw_app_meta_data ->> 'role',
    'user'
  );

  if previous_role = 'owner' then
    raise exception 'Owner accounts cannot be changed here.' using errcode = '42501';
  end if;

  update auth.users
  set raw_app_meta_data =
    coalesce(raw_app_meta_data, '{}'::jsonb)
    || jsonb_build_object('role', normalized_role)
  where id = target_record.id;

  insert into public.role_assignment_audit (
    assigned_by,
    target_user_id,
    target_email,
    previous_role,
    new_role
  ) values (
    auth.uid(),
    target_record.id,
    normalized_email,
    previous_role,
    normalized_role
  );

  return jsonb_build_object(
    'email', normalized_email,
    'previous_role', previous_role,
    'role', normalized_role
  );
end;
$$;

revoke all on function public.assign_user_role(text, text) from public;
grant execute on function public.assign_user_role(text, text) to authenticated;
