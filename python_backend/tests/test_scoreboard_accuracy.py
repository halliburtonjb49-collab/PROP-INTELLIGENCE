import main


def test_scoreboard_dedupe_preserves_doubleheaders() -> None:
    early_game = {
        "id": "game-early",
        "league": "MLB",
        "away_team": "Atlanta Braves",
        "home_team": "New York Mets",
        "startTimeUtc": "2026-07-29T17:10:00Z",
    }
    late_game = {
        **early_game,
        "id": "game-late",
        "startTimeUtc": "2026-07-29T23:10:00Z",
    }

    assert main._scoreboard_dedupe_key(early_game) != main._scoreboard_dedupe_key(
        late_game
    )


def test_scoreboard_dedupe_collapses_same_fallback_event() -> None:
    provider_a = {
        "league": "MLB",
        "away_team": "Seattle Mariners",
        "home_team": "Los Angeles Dodgers",
        "startTimeUtc": "2026-07-30T02:10:00Z",
    }
    provider_b = {
        **provider_a,
        "start_time": provider_a["startTimeUtc"],
    }

    assert main._scoreboard_dedupe_key(provider_a) == main._scoreboard_dedupe_key(
        provider_b
    )
