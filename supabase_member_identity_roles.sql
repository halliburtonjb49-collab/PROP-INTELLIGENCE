-- Owner-controlled complimentary access, numbered founders, and trusted chat identity.
-- Run after supabase_owner_role_manager.sql and supabase_prop_chat_v6.sql.
begin;

alter table public.user_profiles
  add column if not exists assigned_member_role text
    check (assigned_member_role in ('core', 'pro', 'pro_founder')),
  add column if not exists founder_number integer
    check (founder_number between 1 and 999),
  add column if not exists access_granted_by uuid references auth.users(id),
  add column if not exists access_granted_at timestamptz;

create unique index if not exists user_profiles_founder_number_unique
  on public.user_profiles(founder_number)
  where founder_number is not null;

alter table public.user_profiles
  drop constraint if exists user_profiles_founder_number_role_check;
alter table public.user_profiles
  add constraint user_profiles_founder_number_role_check check (
    (assigned_member_role = 'pro_founder' and founder_number is not null)
    or (assigned_member_role is distinct from 'pro_founder' and founder_number is null)
  );

revoke update (
  assigned_member_role,
  founder_number,
  access_granted_by,
  access_granted_at
) on public.user_profiles from authenticated;

create or replace function public.prevent_member_access_self_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.assigned_member_role is not null
       or new.founder_number is not null
       or new.access_granted_by is not null
       or new.access_granted_at is not null then
      if public.effective_account_role() <> 'owner' then
        raise exception 'Only the owner can grant complimentary access.'
          using errcode = '42501';
      end if;
    end if;
  elsif new.assigned_member_role is distinct from old.assigned_member_role
     or new.founder_number is distinct from old.founder_number
     or new.access_granted_by is distinct from old.access_granted_by
     or new.access_granted_at is distinct from old.access_granted_at then
    if public.effective_account_role() <> 'owner' then
      raise exception 'Only the owner can change complimentary access.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_member_access_self_assignment
  on public.user_profiles;
create trigger trg_prevent_member_access_self_assignment
before insert or update on public.user_profiles
for each row execute function public.prevent_member_access_self_assignment();

create table if not exists public.member_access_grant_audit (
  id bigint generated always as identity primary key,
  assigned_by uuid not null references auth.users(id),
  target_user_id uuid not null references auth.users(id),
  target_email text not null,
  previous_account_role text not null,
  new_account_role text not null,
  previous_member_role text,
  new_member_role text,
  previous_founder_number integer,
  new_founder_number integer,
  created_at timestamptz not null default now()
);

alter table public.member_access_grant_audit enable row level security;
drop policy if exists "owner reads member access audit"
  on public.member_access_grant_audit;
create policy "owner reads member access audit"
on public.member_access_grant_audit for select to authenticated
using (public.effective_account_role() = 'owner');

create or replace function public.assign_member_identity_role(
  target_email text,
  target_role text,
  target_founder_number integer default null
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
  previous_account_role text;
  next_account_role text;
  previous_member_role text;
  previous_founder_number integer;
  next_member_role text;
  next_founder_number integer;
begin
  if public.effective_account_role() <> 'owner' then
    raise exception 'Only the owner can assign access roles.' using errcode = '42501';
  end if;
  if normalized_role not in ('admin', 'core', 'pro', 'pro_founder', 'user') then
    raise exception 'Role must be Admin, Core, Pro, Pro Founder, or User.'
      using errcode = '22023';
  end if;
  if normalized_role = 'pro_founder' and
     (target_founder_number is null or target_founder_number not between 1 and 999) then
    raise exception 'Pro Founder requires a unique number from 1 to 999.'
      using errcode = '22023';
  end if;
  if normalized_role <> 'pro_founder' and target_founder_number is not null then
    raise exception 'Founder numbers may only be assigned to Pro Founders.'
      using errcode = '22023';
  end if;

  select * into target_record from auth.users
  where lower(email) = normalized_email limit 1;
  if target_record.id is null then
    raise exception 'No registered user exists for that email.' using errcode = 'P0002';
  end if;

  previous_account_role := lower(coalesce(target_record.raw_app_meta_data->>'role', 'user'));
  if previous_account_role = 'owner' or normalized_email = 'halliburtonjb49@gmail.com' then
    raise exception 'Owner accounts cannot be changed here.' using errcode = '42501';
  end if;

  select assigned_member_role, founder_number
  into previous_member_role, previous_founder_number
  from public.user_profiles where id = target_record.id;

  next_account_role := case when normalized_role = 'admin' then 'admin' else 'user' end;
  next_member_role := case
    when normalized_role in ('core', 'pro', 'pro_founder') then normalized_role
    else null
  end;
  next_founder_number := case
    when normalized_role = 'pro_founder' then target_founder_number
    else null
  end;

  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
    || jsonb_build_object('role', next_account_role)
  where id = target_record.id;

  insert into public.user_profiles (
    id, email, assigned_member_role, founder_number,
    access_granted_by, access_granted_at
  ) values (
    target_record.id, normalized_email, next_member_role, next_founder_number,
    case when next_member_role is null and next_account_role = 'user' then null else auth.uid() end,
    case when next_member_role is null and next_account_role = 'user' then null else now() end
  ) on conflict (id) do update set
    assigned_member_role = excluded.assigned_member_role,
    founder_number = excluded.founder_number,
    access_granted_by = excluded.access_granted_by,
    access_granted_at = excluded.access_granted_at;

  insert into public.member_access_grant_audit (
    assigned_by, target_user_id, target_email,
    previous_account_role, new_account_role,
    previous_member_role, new_member_role,
    previous_founder_number, new_founder_number
  ) values (
    auth.uid(), target_record.id, normalized_email,
    previous_account_role, next_account_role,
    previous_member_role, next_member_role,
    previous_founder_number, next_founder_number
  );

  return jsonb_build_object(
    'email', normalized_email,
    'role', normalized_role,
    'account_role', next_account_role,
    'assigned_member_role', next_member_role,
    'founder_number', next_founder_number
  );
exception
  when unique_violation then
    raise exception 'That founder number is already assigned.' using errcode = '23505';
end;
$$;

revoke all on function public.assign_member_identity_role(text, text, integer) from public;
grant execute on function public.assign_member_identity_role(text, text, integer)
  to authenticated;

create or replace function public.prop_chat_access_level()
returns integer language sql stable security definer set search_path = public, auth as $$
  select case
    when coalesce((select raw_app_meta_data->>'role' from auth.users where id = auth.uid()), '') in ('owner','admin') then 2
    when coalesce((select assigned_member_role from public.user_profiles where id = auth.uid()), '') in ('pro','pro_founder') then 2
    when coalesce((select subscription_tier from public.user_profiles where id = auth.uid()), 'free') in ('edge','pro') then 2
    when coalesce((select is_premium from public.user_profiles where id = auth.uid()), false) then 2
    when coalesce((select assigned_member_role from public.user_profiles where id = auth.uid()), '') = 'core' then 1
    when coalesce((select subscription_tier from public.user_profiles where id = auth.uid()), 'free') = 'core' then 1
    else 0
  end;
$$;

alter table public.prop_chat_messages
  add column if not exists author_badge_number integer;

create or replace function public.enforce_prop_chat_message_v4()
returns trigger language plpgsql security definer set search_path = public, auth as $$
declare candidate text; app_role text; profile_role text; profile_verified boolean;
  member_role text; member_number integer; paid_tier text;
  active_restriction text; blocked_term text;
begin
  if new.user_id <> auth.uid() or not public.can_access_prop_chat_room(new.room_id) then
    raise exception 'Room access denied';
  end if;
  select restriction into active_restriction from public.prop_chat_restrictions
  where user_id = new.user_id and restriction in ('muted','suspended','banned')
    and (expires_at is null or expires_at > now());
  if active_restriction is not null then raise exception 'Chat access is currently restricted'; end if;
  select coalesce(nullif(trim(p.username), ''), 'user_' || left(replace(new.user_id::text, '-', ''), 8)),
    coalesce(u.raw_app_meta_data->>'role','user'), coalesce(p.chat_role,'member'),
    coalesce(p.chat_verified,false), p.assigned_member_role, p.founder_number,
    coalesce(p.subscription_tier,'free')
  into candidate, app_role, profile_role, profile_verified, member_role, member_number, paid_tier
  from auth.users u left join public.user_profiles p on p.id=u.id where u.id=new.user_id;
  new.username := left(candidate,24);
  new.author_role := case
    when app_role in ('owner','admin') then app_role
    when member_role in ('core','pro','pro_founder') then member_role
    when profile_verified and profile_role in ('expert','creator') then profile_role
    when paid_tier in ('edge','pro') then 'pro'
    when paid_tier = 'core' then 'core'
    else 'user'
  end;
  new.author_badge_number := case when member_role = 'pro_founder' then member_number else null end;
  new.body := trim(new.body);
  new.link_url := public.validate_prop_chat_link(new.link_url);
  if new.attachment_kind in ('prop','slip') then
    if public.prop_chat_access_level() < 2 or new.shared_payload is null
       or jsonb_typeof(new.shared_payload) <> 'object'
       or octet_length(new.shared_payload::text) > 20000 then
      raise exception 'Valid Pro shared analysis is required';
    end if;
  elsif new.shared_payload is not null then raise exception 'Unexpected shared payload';
  end if;
  if new.attachment_path is not null and
     new.attachment_path !~ ('^' || new.user_id::text || '/[a-f0-9-]{36}\.(jpg|jpeg|png|webp)$') then
    raise exception 'Invalid attachment path';
  end if;
  select term into blocked_term from public.prop_chat_blocked_terms
    where position(lower(term) in lower(new.body)) > 0 limit 1;
  if blocked_term is not null then raise exception 'Message blocked by community safety filter'; end if;
  if tg_op='INSERT' and (select count(*) from public.prop_chat_messages
    where user_id=new.user_id and created_at > now()-interval '60 seconds') >= 12 then
    raise exception 'Message limit reached. Please wait a moment';
  end if;
  if tg_op='UPDATE' then new.edited_at:=now(); end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_prop_chat_message_v4 on public.prop_chat_messages;
create trigger trg_enforce_prop_chat_message_v4
before insert or update of body, link_url, attachment_path, attachment_kind, shared_payload
on public.prop_chat_messages for each row execute function public.enforce_prop_chat_message_v4();

commit;
