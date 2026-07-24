import json
from pathlib import Path

from services import sportmonks_headshot_service


def _use_map(monkeypatch, path):
    monkeypatch.setattr(sportmonks_headshot_service, "HEADSHOT_MAP_PATH", path)
    sportmonks_headshot_service._load_map.cache_clear()


def test_missing_sportmonks_cache_reports_missing(monkeypatch, tmp_path):
    path = tmp_path / "sportmonks_headshot_map.json"
    _use_map(monkeypatch, path)

    result = sportmonks_headshot_service.sportmonks_headshot_cache_health()

    assert result["status"] == "missing"
    assert result["playerCount"] == 0
    assert result["mode"] == "local-development"


def test_sportmonks_cache_resolves_normalized_name_and_reports_count(
    monkeypatch,
    tmp_path,
):
    path = tmp_path / "sportmonks_headshot_map.json"
    path.write_text(
        json.dumps(
            {
                "updatedAtUtc": "2026-07-24T12:00:00+00:00",
                "players": {
                    "kylian mbappe": "https://cdn.example/mbappe.png",
                },
            }
        ),
        encoding="utf-8",
    )
    _use_map(monkeypatch, path)

    assert (
        sportmonks_headshot_service.sportmonks_headshot_url("Kylian Mbappé")
        == "https://cdn.example/mbappe.png"
    )
    assert sportmonks_headshot_service.sportmonks_headshot_cache_health() == {
        "status": "ok",
        "mode": "local-development",
        "playerCount": 1,
        "updatedAtUtc": "2026-07-24T12:00:00+00:00",
    }


def test_var_data_sportmonks_cache_reports_persistent_mode(monkeypatch):
    _use_map(
        monkeypatch,
        Path("/var/data/sportmonks_headshot_map.json"),
    )

    result = sportmonks_headshot_service.sportmonks_headshot_cache_health()

    assert result["mode"] == "persistent-disk"
