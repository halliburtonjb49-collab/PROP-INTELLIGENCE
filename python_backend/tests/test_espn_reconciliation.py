from services.historical_ingestion_service import reconcile_basketball_logs


def _row(player: str, game: str, points=None, assists=None):
    return {
        "id": game + player, "sport": "WNBA", "league_game_id": game,
        "player_id": player, "player_name": player, "game_date": "2026-07-31",
        "points": points, "assists": assists, "raw": {},
    }


def test_espn_fills_missing_stats_without_replacing_official_values() -> None:
    primary = [_row("Caitlin Clark", "official", points=22, assists=None)]
    espn = [_row("caitlin clark", "espn", points=21, assists=9)]
    merged, audit = reconcile_basketball_logs(primary, espn)
    assert len(merged) == 1
    assert merged[0]["points"] == 22
    assert merged[0]["assists"] == 9
    assert merged[0]["league_game_id"] == "official"
    assert merged[0]["raw"]["espnReconciled"] is True
    assert audit == {"matched": 1, "added": 0, "fieldsFilled": 1}


def test_espn_adds_missing_player_game() -> None:
    merged, audit = reconcile_basketball_logs([], [_row("New Player", "espn", points=10)])
    assert len(merged) == 1
    assert audit == {"matched": 0, "added": 1, "fieldsFilled": 0}
