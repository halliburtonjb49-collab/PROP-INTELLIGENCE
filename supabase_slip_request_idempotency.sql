begin;

-- Keep schema locks in Render's pre-deploy phase. These statements used to
-- run on the first live slip request handled by every process, where their
-- AccessExclusiveLock could deadlock with active ticket writes.
alter table public.slips
  add column if not exists client_request_id text;

create index if not exists slips_user_status_idx
  on public.slips(user_id, status, created_at desc);

create unique index if not exists slips_user_request_idx
  on public.slips(user_id, client_request_id)
  where client_request_id is not null;

commit;
