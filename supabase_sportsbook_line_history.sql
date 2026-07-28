create table if not exists public.sportsbook_line_snapshots (
    id bigserial primary key,
    observed_at timestamptz not null,
    provider text not null,
    sport text not null,
    event_id text not null,
    player text not null,
    market text not null,
    bookmaker text not null,
    line double precision not null,
    over_odds double precision,
    under_odds double precision,
    snapshot_hash text not null unique
);

create index if not exists sportsbook_line_lookup_idx
    on public.sportsbook_line_snapshots
    (sport, event_id, player, market, observed_at desc);

create table if not exists public.prop_market_intelligence (
    id bigserial primary key,
    observed_at timestamptz not null,
    sport text not null,
    event_id text not null,
    player text not null,
    market text not null,
    consensus_line double precision,
    book_count integer not null,
    best_over_odds double precision,
    best_under_odds double precision
);

create index if not exists prop_market_intelligence_lookup_idx
    on public.prop_market_intelligence
    (sport, event_id, player, market, observed_at desc);
