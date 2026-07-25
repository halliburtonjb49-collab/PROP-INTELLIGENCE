import json

from services import mlb_headshot_service


def test_mlb_player_id_uses_the_official_roster_cache(monkeypatch, tmp_path):
    path = tmp_path / "mlb_headshot_map.json"
    path.write_text(
        json.dumps({"players": {"jose ramirez": 608070}}),
        encoding="utf-8",
    )
    monkeypatch.setattr(mlb_headshot_service, "HEADSHOT_MAP_PATH", path)
    mlb_headshot_service._load_map.cache_clear()

    assert mlb_headshot_service.mlb_player_id("José Ramírez") == 608070
    assert "608070" in (
        mlb_headshot_service.mlb_headshot_url("José Ramírez") or ""
    )
