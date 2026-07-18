from services.prop_processor import (
    _opposite_american_odds,
    _player_and_line,
    count_valid_prop_rows,
    process_and_cache_props,
)


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
