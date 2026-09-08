-- Treat the owner's verified Apple login as an additional identity for the
-- same application owner. This preserves the existing owner accounts while
-- allowing Sign in with Apple to bypass subscription gates securely.
begin;

insert into public.app_owner_accounts (user_id)
select id
from auth.users
where lower(email) in (
  'propsintell@gmail.com',
  'propsintell@icloud.com',
  'halliburtonjb49@gmail.com'
)
on conflict (user_id) do nothing;

update auth.users
set raw_app_meta_data =
  coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'owner')
where lower(email) in (
  'propsintell@gmail.com',
  'propsintell@icloud.com',
  'halliburtonjb49@gmail.com'
);

create or replace function public.is_app_owner(
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.app_owner_accounts
    where user_id = target_user_id
  ) or exists (
    select 1
    from auth.users
    where id = target_user_id
      and lower(email) in (
        'propsintell@gmail.com',
        'propsintell@icloud.com',
        'halliburtonjb49@gmail.com'
      )
  );
$$;

revoke all on function public.is_app_owner(uuid) from public;
grant execute on function public.is_app_owner(uuid) to authenticated;

commit;
