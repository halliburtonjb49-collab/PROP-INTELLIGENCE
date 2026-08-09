from services.prop_processor import (
    _opposite_american_odds,
    _player_and_line,
    count_valid_prop_rows,
    process_and_cache_props,
)
from database.cache import PropCache


class CacheThatMustNotBeCleared:
    def clear_game_props(self, _event_id: str) -> None:
        raise AssertionError("A failed provider response must preserve cached props")


def test_empty_provider_payload_preserves_existing_event_cache() -> None:
    inserted = process_and_cache_props(
        cache=CacheThatMustNotBeCleared(),
        sport_key="baseball_mlb",
        event={"id": "event-1"},
        odds_payload={"bookmakers": []},
    )
    assert inserted == 0


def test_valid_prop_rows_require_player_and_numeric_line() -> None:
    payload = {
        "bookmakers": [
            {
                "markets": [
                    {
                        "outcomes": [
                            {"description": "Player One", "point": 1.5},
                            {"description": "Player Two", "point": None},
                            {"description": "", "point": 2.5},
                        ]
                    }
                ]
            }
        ]
    }
    assert count_valid_prop_rows(payload) == 1


def test_binary_player_markets_accept_named_and_yes_no_formats() -> None:
    assert _player_and_line(
        "player_anytime_td", {"name": "Josh Allen", "price": 130}
    ) == ("Josh Allen", 0.5)
    assert _player_and_line(
        "player_double_double", {"name": "Yes", "description": "A'ja Wilson", "price": -120}
    ) == ("A'ja Wilson", 0.5)
    payload = {"bookmakers": [{"markets": [{
        "key": "player_goal_scorer_anytime",
        "outcomes": [{"name": "Lionel Messi", "price": 115}],
    }]}]}
    assert count_valid_prop_rows(payload) == 1
    assert _opposite_american_odds(100) == -100


def test_event_props_are_replaced_in_one_cache_transaction(tmp_path) -> None:
    cache = PropCache(tmp_path / "props.db")
    payload = {"bookmakers": [{
        "title": "Book",
        "markets": [{
            "key": "player_points",
            "outcomes": [
                {"name": "Over", "description": "Player One", "point": 20.5, "price": -105},
                {"name": "Under", "description": "Player One", "point": 20.5, "price": -115},
            ],
        }],
    }]}

    inserted = process_and_cache_props(
        cache=cache,
        sport_key="basketball_nba",
        event={
            "id": "event-1", "home_team": "Home", "away_team": "Away",
            "commence_time": "2026-07-18T23:00:00Z",
        },
        odds_payload=payload,
    )

    assert inserted == 1
    rows = cache.load_props()
    assert len(rows) == 1
    assert rows[0]["player_name"] == "Player One"
    assert rows[0]["over_odds"] == -105
    assert rows[0]["under_odds"] == -115


def test_unpaired_player_line_is_not_published(tmp_path) -> None:
    cache = PropCache(tmp_path / "unpaired.db")
    payload = {"bookmakers": [{
        "title": "PrizePicks",
        "markets": [{
            "key": "player_points",
            "outcomes": [
                {"name": "Over", "description": "Player One", "point": 20.5, "price": -110},
            ],
        }],
    }]}

    inserted = process_and_cache_props(
        cache=cache,
        sport_key="basketball_wnba",
        event={"id": "wnba-1", "commence_time": "2099-07-18T23:00:00Z"},
        odds_payload=payload,
    )

    assert inserted == 0
    assert cache.load_props() == []


def test_team_scale_total_is_not_published_as_wnba_player_points(tmp_path) -> None:
    cache = PropCache(tmp_path / "team-total.db")
    payload = {"bookmakers": [{
        "title": "PrizePicks",
        "markets": [{
            "key": "player_points",
            "outcomes": [
                {"name": "Over", "description": "Player One", "point": 167.5, "price": -110},
                {"name": "Under", "description": "Player One", "point": 167.5, "price": -110},
            ],
        }],
    }]}

    inserted = process_and_cache_props(
        cache=cache,
        sport_key="basketball_wnba",
        event={"id": "wnba-2", "commence_time": "2099-07-18T23:00:00Z"},
        odds_payload=payload,
    )

    assert inserted == 0
    assert cache.load_props() == []


def test_line_change_preserves_opening_line_and_updates_current_line(tmp_path) -> None:
    cache = PropCache(tmp_path / "line-move.db")

    def payload(line: float) -> dict[str, object]:
        return {"bookmakers": [{
            "title": "FanDuel",
            "markets": [{
                "key": "player_points",
                "outcomes": [
                    {"name": "Over", "description": "Player One", "point": line, "price": -105},
                    {"name": "Under", "description": "Player One", "point": line, "price": -115},
                ],
            }],
        }]}

    event = {
        "id": "event-1",
        "home_team": "Home",
        "away_team": "Away",
        "commence_time": "2099-07-18T23:00:00Z",
    }
    process_and_cache_props(
        cache=cache,
        sport_key="basketball_nba",
        event=event,
        odds_payload=payload(20.5),
    )
    process_and_cache_props(
        cache=cache,
        sport_key="basketball_nba",
        event=event,
        odds_payload=payload(21.5),
    )

    row = cache.load_props()[0]
    assert row["line"] == 21.5
    assert row["opening_line"] == 20.5
    assert row["current_line"] == 21.5

def test_durable_history_restores_opening_line_after_cache_reset(tmp_path, monkeypatch) -> None:
    cache = PropCache(tmp_path / "restored-line-move.db")
    monkeypatch.setattr(
        "services.prop_processor.opening_line_snapshots",
        lambda **_kwargs: {
            ("fanduel", "player_points", "player one"): {
                "opening_line": 20.5,
                "line_updated_at": "2026-08-01T12:00:00+00:00",
            },
        },
    )
    payload = {"bookmakers": [{
        "title": "FanDuel",
        "markets": [{
            "key": "player_points",
            "outcomes": [
                {"name": "Over", "description": "Player One", "point": 21.5, "price": -105},
                {"name": "Under", "description": "Player One", "point": 21.5, "price": -115},
            ],
        }],
    }]}

    process_and_cache_props(
        cache=cache,
        sport_key="basketball_nba",
        event={"id": "event-1", "commence_time": "2099-07-18T23:00:00Z"},
        odds_payload=payload,
    )

    row = cache.load_props()[0]
    assert row["opening_line"] == 20.5
    assert row["current_line"] == 21.5
