from services.prop_processor import count_valid_prop_rows, process_and_cache_props


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
