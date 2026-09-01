-- Rebind the one application owner to the production Google account used to
-- administer PROP INTELLIGENCE. Runtime authorization remains UUID-based.
begin;

delete from public.app_owner_accounts
where user_id <> '7fdb460c-dcaa-42ac-89c1-e9950b9b9c55'::uuid;

insert into public.app_owner_accounts (user_id)
values ('7fdb460c-dcaa-42ac-89c1-e9950b9b9c55'::uuid)
on conflict (user_id) do nothing;

update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'role'
where id <> '7fdb460c-dcaa-42ac-89c1-e9950b9b9c55'::uuid
  and coalesce(raw_app_meta_data->>'role', '') = 'owner';

update auth.users
set raw_app_meta_data =
  coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'owner')
where id = '7fdb460c-dcaa-42ac-89c1-e9950b9b9c55'::uuid;

commit;
