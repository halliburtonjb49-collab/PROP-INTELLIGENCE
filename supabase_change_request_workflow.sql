-- Admin-to-owner change approval workflow.
-- Run once in the Supabase SQL editor after supabase_owner_role_manager.sql.

create table if not exists public.app_change_requests (
  id bigint generated always as identity primary key,
  requested_by uuid not null references auth.users(id) on delete cascade,
  requester_email text not null,
  title text not null check (char_length(title) between 3 and 120),
  description text not null check (char_length(description) between 10 and 4000),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'denied')),
  owner_response text,
  reviewed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists app_change_requests_status_created_idx
  on public.app_change_requests(status, created_at desc);

alter table public.app_change_requests enable row level security;

create or replace function public.effective_account_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when lower(coalesce(auth.jwt() ->> 'email', '')) =
      'halliburtonjb49@gmail.com' then 'owner'
    else lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', 'user'))
  end;
$$;

create or replace function public.submit_app_change_request(
  request_title text,
  request_description text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_title text := trim(request_title);
  normalized_description text := trim(request_description);
  inserted public.app_change_requests%rowtype;
begin
  if public.effective_account_role() <> 'admin' then
    raise exception 'Only administrators can submit change requests.'
      using errcode = '42501';
  end if;
  if char_length(normalized_title) not between 3 and 120 then
    raise exception 'Title must contain 3 to 120 characters.'
      using errcode = '22023';
  end if;
  if char_length(normalized_description) not between 10 and 4000 then
    raise exception 'Description must contain 10 to 4000 characters.'
      using errcode = '22023';
  end if;

  insert into public.app_change_requests (
    requested_by,
    requester_email,
    title,
    description
  ) values (
    auth.uid(),
    lower(coalesce(auth.jwt() ->> 'email', 'unknown')),
    normalized_title,
    normalized_description
  ) returning * into inserted;

  return to_jsonb(inserted);
end;
$$;

create or replace function public.list_app_change_requests()
returns setof public.app_change_requests
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.effective_account_role() = 'owner' then
    return query
      select * from public.app_change_requests
      order by
        case when status = 'pending' then 0 else 1 end,
        created_at desc;
  elsif public.effective_account_role() = 'admin' then
    return query
      select * from public.app_change_requests
      where requested_by = auth.uid()
      order by created_at desc;
  else
    raise exception 'Change requests are available to owners and administrators.'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.review_app_change_request(
  request_id bigint,
  decision text,
  response text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_decision text := lower(trim(decision));
  updated public.app_change_requests%rowtype;
begin
  if public.effective_account_role() <> 'owner' then
    raise exception 'Only the owner can review change requests.'
      using errcode = '42501';
  end if;
  if normalized_decision not in ('approved', 'denied') then
    raise exception 'Decision must be approved or denied.'
      using errcode = '22023';
  end if;

  update public.app_change_requests
  set status = normalized_decision,
      owner_response = nullif(trim(response), ''),
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      updated_at = now()
  where id = request_id and status = 'pending'
  returning * into updated;

  if updated.id is null then
    raise exception 'Pending change request not found.' using errcode = 'P0002';
  end if;
  return to_jsonb(updated);
end;
$$;

revoke all on function public.effective_account_role() from public;
revoke all on function public.submit_app_change_request(text, text) from public;
revoke all on function public.list_app_change_requests() from public;
revoke all on function public.review_app_change_request(bigint, text, text) from public;
grant execute on function public.submit_app_change_request(text, text) to authenticated;
grant execute on function public.list_app_change_requests() to authenticated;
grant execute on function public.review_app_change_request(bigint, text, text) to authenticated;
