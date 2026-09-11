from pathlib import Path

from database.cache import PropCache


def test_prune_sports_removes_games_and_props_for_disabled_leagues(tmp_path) -> None:
    cache = PropCache(Path(tmp_path / "props.db"))
    for sport, game_id in (("baseball_mlb", "mlb-1"), ("americanfootball_ncaaf", "college-1")):
        cache.replace_event_props(
            sport=sport,
            game={
                "id": game_id,
                "home_team": "Home",
                "away_team": "Away",
                "commence_time": "2026-09-11T20:00:00Z",
            },
            props=[
                (
                    game_id, "Player", "Market", 1.5, 1.5, 1.5, "", -110,
                    -110, "book", 1.7, 80, "", None, None, None, None, None,
                    None, None, None, None, "2026-09-11T12:00:00Z",
                )
            ],
        )

    cache.prune_sports(["americanfootball_ncaaf"])

    rows = cache.load_props()
    assert [row["game_id"] for row in rows] == ["mlb-1"]
