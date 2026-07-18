from services.schedule_fatigue_service import VENUES, _distance


def test_arena_registry_covers_current_wnba_markets() -> None:
    assert {"ATL", "CHI", "CON", "DAL", "GSV", "IND", "LAS", "LVA",
            "MIN", "NYL", "PDX", "PHX", "SEA", "TOR", "WAS"} <= set(VENUES)


def test_travel_distance_is_geographically_plausible() -> None:
    atlanta = VENUES["ATL"][:2]
    seattle = VENUES["SEA"][:2]
    assert 2000 < _distance(atlanta, seattle) < 2500
