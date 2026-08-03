create table if not exists public.smartstake_mlb_prop_closes (
    game_id text not null,
    start_time timestamptz not null,
    player text not null,
    market text not null,
    line double precision not null,
    book text not null,
    opening_over_odds double precision,
    opening_under_odds double precision,
    closing_over_odds double precision,
    closing_under_odds double precision,
    opening_at timestamptz,
    closing_at timestamptz,
    result double precision,
    over_won boolean,
    source text not null default 'SmartStake/mlb-player-props',
    source_license text not null default 'CC-BY-4.0',
    imported_at timestamptz not null default now(),
    primary key (game_id, player, market, line, book)
);

create index if not exists smartstake_mlb_prop_closes_time_idx
    on public.smartstake_mlb_prop_closes(start_time, market, book);

alter table public.smartstake_mlb_prop_closes enable row level security;
revoke all on table public.smartstake_mlb_prop_closes from anon, authenticated;

