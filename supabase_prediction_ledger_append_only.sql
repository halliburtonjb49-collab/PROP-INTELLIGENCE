-- Graded predictions form a public audit ledger. They may be enriched with
-- later market context, but their recorded forecast and outcome are immutable.
create or replace function public.protect_graded_prediction_history()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' and old.hit is not null then
    raise exception 'Graded prediction history is append-only';
  end if;

  if tg_op = 'UPDATE' and old.hit is not null and (
    new.prop_id is distinct from old.prop_id or
    new.player_id is distinct from old.player_id or
    new.sport is distinct from old.sport or
    new.market is distinct from old.market or
    new.side is distinct from old.side or
    new.line is distinct from old.line or
    new.projection is distinct from old.projection or
    new.hit_probability is distinct from old.hit_probability or
    new.model_version is distinct from old.model_version or
    new.actual_value is distinct from old.actual_value or
    new.hit is distinct from old.hit or
    new.graded_at is distinct from old.graded_at
  ) then
    raise exception 'Graded prediction results are immutable';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.protect_graded_prediction_history() from public, anon, authenticated;

drop trigger if exists prediction_snapshots_append_only on public.prediction_snapshots;
create trigger prediction_snapshots_append_only
before update or delete on public.prediction_snapshots
for each row execute function public.protect_graded_prediction_history();