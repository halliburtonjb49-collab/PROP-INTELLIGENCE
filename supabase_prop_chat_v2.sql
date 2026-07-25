-- PROP CHAT v2: professional identity, rooms, moderation, replies,
-- reactions, read state, presence, preferences, retention, and health.

begin;

alter table public.user_profiles add column if not exists username text;

update public.user_profiles
set username = 'user_' || left(replace(id::text, '-', ''), 8)
where username is null or char_length(trim(username)) < 3;

create unique index if not exists idx_user_profiles_username_unique
on public.user_profiles(lower(username));

create table if not exists public.prop_chat_rooms (
  id text primary key check (id ~ '^[a-z0-9_]{2,24}$'),
  name text not null,
  position integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.prop_chat_rooms(id, name, position) values
  ('general', 'General', 0),
  ('nba', 'NBA', 10),
  ('wnba', 'WNBA', 20),
  ('mlb', 'MLB', 30),
  ('nfl', 'NFL', 40),
  ('nhl', 'NHL', 50),
  ('soccer', 'Soccer', 60),
  ('pga', 'PGA', 70),
  ('ufc', 'UFC', 80)
on conflict (id) do update
set name = excluded.name, position = excluded.position, is_active = true;

alter table public.prop_chat_messages
  add column if not exists room_id text references public.prop_chat_rooms(id),
  add column if not exists reply_to_id bigint references public.prop_chat_messages(id) on delete set null,
  add column if not exists author_role text not null default 'user',
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz;

update public.prop_chat_messages set room_id = 'general' where room_id is null;
alter table public.prop_chat_messages alter column room_id set default 'general';
alter table public.prop_chat_messages alter column room_id set not null;

create index if not exists idx_prop_chat_messages_room_created
on public.prop_chat_messages(room_id, created_at desc);

create table if not exists public.prop_chat_reactions (
  message_id bigint not null references public.prop_chat_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (emoji in ('👍', '🔥', '👀')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

create table if not exists public.prop_chat_read_state (
  user_id uuid not null references auth.users(id) on delete cascade,
  room_id text not null references public.prop_chat_rooms(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (user_id, room_id)
);

create table if not exists public.prop_chat_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  notifications_enabled boolean not null default true,
  sounds_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.prop_chat_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  room_id text references public.prop_chat_rooms(id) on delete set null,
  is_typing boolean not null default false,
  last_seen_at timestamptz not null default now()
);

create table if not exists public.prop_chat_restrictions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  restriction text not null check (restriction in ('warned', 'muted', 'suspended', 'banned')),
  reason text not null,
  expires_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.prop_chat_reports
  add column if not exists message_body text,
  add column if not exists message_username text,
  add column if not exists message_user_id uuid,
  add column if not exists status text not null default 'open'
    check (status in ('open', 'reviewed', 'resolved', 'dismissed')),
  add column if not exists reviewed_by uuid references auth.users(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists resolution_note text;

alter table public.prop_chat_reports
  drop constraint if exists prop_chat_reports_message_id_fkey;
alter table public.prop_chat_reports
  add constraint prop_chat_reports_message_id_fkey
  foreign key (message_id) references public.prop_chat_messages(id) on delete set null;
alter table public.prop_chat_reports alter column message_id drop not null;

create or replace function public.is_prop_chat_moderator()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(auth.jwt()->'app_metadata'->>'role', '') in ('owner', 'admin')
    or lower(coalesce(auth.jwt()->>'email', '')) = 'halliburtonjb49@gmail.com';
$$;

create or replace function public.set_prop_chat_public_username(requested text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  normalized := lower(trim(requested));
  if normalized !~ '^[a-z][a-z0-9_]{2,23}$' then
    raise exception 'Username must start with a letter and use 3-24 letters, numbers, or underscores';
  end if;
  if normalized in ('admin', 'administrator', 'moderator', 'mod', 'support',
    'propsintell', 'propintelligence', 'owner', 'staff', 'system') then
    raise exception 'That username is reserved';
  end if;

  insert into public.user_profiles(id, email, username, display_name)
  select auth.uid(), email, normalized, normalized
  from auth.users where id = auth.uid()
  on conflict (id) do update
  set username = excluded.username,
      display_name = excluded.display_name,
      updated_at = now();
  return normalized;
exception
  when unique_violation then raise exception 'That username is already taken';
end;
$$;

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
begin
  if tg_op = 'INSERT' and new.user_id <> auth.uid() then
    raise exception 'Messages may only be sent as the authenticated user';
  end if;
  if tg_op = 'UPDATE' and old.user_id <> auth.uid() and not public.is_prop_chat_moderator() then
    raise exception 'Message update not allowed';
  end if;

  select restriction into active_restriction
  from public.prop_chat_restrictions
  where user_id = new.user_id
    and restriction in ('muted', 'suspended', 'banned')
    and (expires_at is null or expires_at > now());
  if active_restriction is not null then
    raise exception 'Chat access is currently restricted';
  end if;

  select coalesce(nullif(trim(p.username), ''), 'user_' || left(replace(new.user_id::text, '-', ''), 8)),
         coalesce(u.raw_app_meta_data->>'role', 'user')
  into candidate, role_value
  from auth.users u
  left join public.user_profiles p on p.id = u.id
  where u.id = new.user_id;

  new.username := left(candidate, 24);
  new.author_role := case when role_value in ('owner', 'admin') then role_value else 'user' end;
  new.body := trim(new.body);

  if new.body ~* '(https?://|www\.|[a-z0-9-]+\.(com|net|org|io)(/|\s|$))' then
    raise exception 'Links are not allowed in PROP CHAT';
  end if;
  if new.body ~* '\m(free money|guaranteed lock|dm me|send cash|wire transfer)\M' then
    raise exception 'Message blocked by community safety filter';
  end if;
  if tg_op = 'INSERT' and (
    select count(*) from public.prop_chat_messages
    where user_id = new.user_id and created_at > now() - interval '60 seconds'
  ) >= 12 then
    raise exception 'Message limit reached. Please wait a moment';
  end if;
  if tg_op = 'UPDATE' then new.edited_at := now(); end if;
  return new;
end;
$$;

drop trigger if exists trg_set_prop_chat_username on public.prop_chat_messages;
drop trigger if exists trg_enforce_prop_chat_message_v2 on public.prop_chat_messages;
create trigger trg_enforce_prop_chat_message_v2
before insert or update of body on public.prop_chat_messages
for each row execute function public.enforce_prop_chat_message_v2();

create or replace function public.capture_prop_chat_report()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  select body, username, user_id
  into new.message_body, new.message_username, new.message_user_id
  from public.prop_chat_messages where id = new.message_id;
  return new;
end;
$$;

drop trigger if exists trg_capture_prop_chat_report on public.prop_chat_reports;
create trigger trg_capture_prop_chat_report
before insert on public.prop_chat_reports
for each row execute function public.capture_prop_chat_report();

alter table public.prop_chat_rooms enable row level security;
alter table public.prop_chat_reactions enable row level security;
alter table public.prop_chat_read_state enable row level security;
alter table public.prop_chat_preferences enable row level security;
alter table public.prop_chat_presence enable row level security;
alter table public.prop_chat_restrictions enable row level security;

create policy prop_chat_rooms_read on public.prop_chat_rooms
for select to authenticated using (is_active or public.is_prop_chat_moderator());

create policy prop_chat_reactions_read on public.prop_chat_reactions
for select to authenticated using (true);
create policy prop_chat_reactions_insert on public.prop_chat_reactions
for insert to authenticated with check (auth.uid() = user_id);
create policy prop_chat_reactions_delete on public.prop_chat_reactions
for delete to authenticated using (auth.uid() = user_id);

create policy prop_chat_read_state_own on public.prop_chat_read_state
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy prop_chat_preferences_own on public.prop_chat_preferences
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy prop_chat_presence_read on public.prop_chat_presence
for select to authenticated using (last_seen_at > now() - interval '2 minutes');
create policy prop_chat_presence_own on public.prop_chat_presence
for insert to authenticated with check (auth.uid() = user_id);
create policy prop_chat_presence_update on public.prop_chat_presence
for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy prop_chat_restrictions_read on public.prop_chat_restrictions
for select to authenticated using (auth.uid() = user_id or public.is_prop_chat_moderator());
create policy prop_chat_restrictions_moderate on public.prop_chat_restrictions
for all to authenticated using (public.is_prop_chat_moderator())
with check (public.is_prop_chat_moderator());

drop policy if exists prop_chat_messages_read on public.prop_chat_messages;
create policy prop_chat_messages_read on public.prop_chat_messages
for select to authenticated using (deleted_at is null or public.is_prop_chat_moderator());
drop policy if exists prop_chat_messages_delete on public.prop_chat_messages;
create policy prop_chat_messages_delete on public.prop_chat_messages
for delete to authenticated using (auth.uid() = user_id or public.is_prop_chat_moderator());
create policy prop_chat_messages_edit on public.prop_chat_messages
for update to authenticated using (
  (auth.uid() = user_id and created_at > now() - interval '5 minutes')
  or public.is_prop_chat_moderator()
) with check (auth.uid() = user_id or public.is_prop_chat_moderator());

drop policy if exists prop_chat_reports_read on public.prop_chat_reports;
create policy prop_chat_reports_read on public.prop_chat_reports
for select to authenticated using (auth.uid() = reporter_id or public.is_prop_chat_moderator());
create policy prop_chat_reports_moderate on public.prop_chat_reports
for update to authenticated using (public.is_prop_chat_moderator())
with check (public.is_prop_chat_moderator());

create or replace function public.prop_chat_health()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'status', 'healthy',
    'messages_24h', (select count(*) from prop_chat_messages where created_at > now() - interval '24 hours'),
    'open_reports', (select count(*) from prop_chat_reports where status = 'open'),
    'online_users', (select count(*) from prop_chat_presence where last_seen_at > now() - interval '2 minutes'),
    'checked_at', now()
  );
$$;

create or replace function public.prune_prop_chat(retention_days integer default 90)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare removed integer;
begin
  if not public.is_prop_chat_moderator() then raise exception 'Moderator access required'; end if;
  delete from public.prop_chat_messages
  where created_at < now() - make_interval(days => greatest(retention_days, 30));
  get diagnostics removed = row_count;
  return removed;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.prop_chat_reactions;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.prop_chat_presence;
exception when duplicate_object then null;
end $$;

commit;
