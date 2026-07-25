-- Bind the verified application owner to an immutable Supabase user ID.
-- Owner access is independent of subscription state, email changes, or stale JWT role claims.

begin;

create table if not exists public.app_owner_accounts (
  user_id uuid primary key references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

insert into public.app_owner_accounts(user_id)
values ('84a76503-f704-46b6-be87-760ea8c9f2f5')
on conflict (user_id) do nothing;

update auth.users
set raw_app_meta_data =
  coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'owner')
where id = '84a76503-f704-46b6-be87-760ea8c9f2f5';

alter table public.app_owner_accounts enable row level security;
alter table public.app_owner_accounts force row level security;

create or replace function public.is_app_owner(
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_owner_accounts where user_id = target_user_id
  );
$$;

revoke all on function public.is_app_owner(uuid) from public;
grant execute on function public.is_app_owner(uuid) to authenticated;

drop policy if exists app_owner_read_own on public.app_owner_accounts;
create policy app_owner_read_own on public.app_owner_accounts
for select to authenticated using (user_id = auth.uid());

create or replace function public.is_prop_chat_moderator()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select public.is_app_owner(auth.uid())
    or coalesce(auth.jwt()->'app_metadata'->>'role', '') in ('owner', 'admin');
$$;

delete from public.prop_chat_restrictions
where public.is_app_owner(user_id);

create or replace function public.prevent_owner_chat_restriction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_app_owner(new.user_id) then
    raise exception 'The application owner cannot be restricted';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_owner_chat_restriction
on public.prop_chat_restrictions;
create trigger trg_prevent_owner_chat_restriction
before insert or update on public.prop_chat_restrictions
for each row execute function public.prevent_owner_chat_restriction();

create or replace function public.enforce_prop_chat_message_v2()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  candidate text;
  role_value text;
  active_restriction text;
  blocked_term text;
  owner_account boolean;
begin
  owner_account := public.is_app_owner(new.user_id);
  if tg_op = 'INSERT' and new.user_id <> auth.uid() then
    raise exception 'Messages may only be sent as the authenticated user';
  end if;
  if tg_op = 'UPDATE' and old.user_id <> auth.uid() and not public.is_prop_chat_moderator() then
    raise exception 'Message update not allowed';
  end if;

  if not owner_account then
    select restriction into active_restriction
    from public.prop_chat_restrictions
    where user_id = new.user_id
      and restriction in ('muted', 'suspended', 'banned')
      and (expires_at is null or expires_at > now());
    if active_restriction is not null then
      raise exception 'Chat access is currently restricted';
    end if;
  end if;

  select coalesce(nullif(trim(p.username), ''), 'user_' || left(replace(new.user_id::text, '-', ''), 8)),
         coalesce(u.raw_app_meta_data->>'role', 'user')
  into candidate, role_value
  from auth.users u
  left join public.user_profiles p on p.id = u.id
  where u.id = new.user_id;

  new.username := left(candidate, 24);
  new.author_role := case
    when owner_account then 'owner'
    when role_value in ('owner', 'admin') then role_value
    else 'user'
  end;
  new.body := trim(new.body);

  if not owner_account then
    if new.body ~* '(https?://|www\.|[a-z0-9-]+\.(com|net|org|io)(/|\s|$))' then
      raise exception 'Links are not allowed in PROP CHAT';
    end if;
    select term into blocked_term
    from public.prop_chat_blocked_terms
    where position(lower(term) in lower(new.body)) > 0
    limit 1;
    if blocked_term is not null then
      raise exception 'Message blocked by community safety filter';
    end if;
    if tg_op = 'INSERT' and (
      select count(*) from public.prop_chat_messages
      where user_id = new.user_id and created_at > now() - interval '60 seconds'
    ) >= 12 then
      raise exception 'Message limit reached. Please wait a moment';
    end if;
  end if;

  if tg_op = 'UPDATE' then new.edited_at := now(); end if;
  return new;
end;
$$;

commit;
