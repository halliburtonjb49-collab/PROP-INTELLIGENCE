-- Extend the existing owner approval workflow to advisor accounts.
-- This is additive because applied migrations are immutable.

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
  if public.effective_account_role() not in ('advisor', 'admin') then
    raise exception 'Only advisors can submit change requests.'
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
  elsif public.effective_account_role() in ('advisor', 'admin') then
    return query
      select * from public.app_change_requests
      where requested_by = auth.uid()
      order by created_at desc;
  else
    raise exception 'Change requests are available to owners and advisors.'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.submit_app_change_request(text, text) from public;
revoke all on function public.list_app_change_requests() from public;
grant execute on function public.submit_app_change_request(text, text) to authenticated;
grant execute on function public.list_app_change_requests() to authenticated;
