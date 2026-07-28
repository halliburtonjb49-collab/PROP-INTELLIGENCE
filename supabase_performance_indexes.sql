-- Indexes for the projection-history queries exercised by the live prop cache.
create index if not exists basketball_player_name_history_idx
  on public.historical_basketball_game_logs(
    sport,
    lower(player_name),
    game_date desc,
    updated_at desc
  );

create index if not exists mlb_batter_date_idx
  on public.historical_mlb_pitches(batter_id, game_date desc)
  where batter_id <> '';
