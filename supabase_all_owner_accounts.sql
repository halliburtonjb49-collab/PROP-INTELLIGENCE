-- Keep every established application-owner login authoritative across web,
-- API, RLS, and restored browser sessions.
begin;

insert into public.app_owner_accounts(user_id)
select id
from auth.users
where id in (
  '7fdb460c-dcaa-42ac-89c1-e9950b9b9c55'::uuid,
  '84a76503-f704-46b6-be87-760ea8c9f2f5'::uuid
)
or lower(email) in (
  'propsintell@gmail.com',
  'halliburtonjb49@gmail.com'
)
on conflict (user_id) do nothing;

update auth.users
set raw_app_meta_data =
  coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'owner')
where id in (select user_id from public.app_owner_accounts)
and (
  id in (
    '7fdb460c-dcaa-42ac-89c1-e9950b9b9c55'::uuid,
    '84a76503-f704-46b6-be87-760ea8c9f2f5'::uuid
  )
  or lower(email) in (
    'propsintell@gmail.com',
    'halliburtonjb49@gmail.com'
  )
);

update public.user_profiles
set assigned_member_role = 'owner',
    subscription_tier = 'edge',
    is_premium = true,
    updated_at = now()
where id in (select user_id from public.app_owner_accounts);

commit;
