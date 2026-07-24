import json
from pathlib import Path

from services import espn_headshot_service


def _use_map(monkeypatch, path):
    monkeypatch.setattr(espn_headshot_service, "HEADSHOT_MAP_PATH", path)
    espn_headshot_service._load_map.cache_clear()


def test_espn_cache_resolves_pga_and_ufc_headshots(monkeypatch, tmp_path):
    path = tmp_path / "espn_headshot_map.json"
    path.write_text(
        json.dumps(
            {
                "updatedAtUtc": "2026-07-24T12:00:00+00:00",
                "leagues": {
                    "PGA": {"rory mcilroy": "https://cdn.example/rory.png"},
                    "UFC": {"jose aldo": "https://cdn.example/aldo.png"},
                },
            }
        ),
        encoding="utf-8",
    )
    _use_map(monkeypatch, path)

    assert (
        espn_headshot_service.espn_headshot_url("Rory McIlroy", "PGA")
        == "https://cdn.example/rory.png"
    )
    assert (
        espn_headshot_service.espn_headshot_url("José Aldo", "UFC")
        == "https://cdn.example/aldo.png"
    )
    health = espn_headshot_service.espn_headshot_cache_health()
    assert health["status"] == "ok"
    assert health["playerCount"] == 2
    assert health["leagueCounts"] == {"PGA": 1, "UFC": 1}


def test_espn_refresh_includes_team_and_event_leagues(monkeypatch, tmp_path):
    path = tmp_path / "espn_headshot_map.json"
    _use_map(monkeypatch, path)
    monkeypatch.setattr(
        espn_headshot_service,
        "LEAGUES",
        {"NBA": ("basketball", "nba")},
    )
    monkeypatch.setattr(
        espn_headshot_service,
        "EVENT_LEAGUES",
        {"PGA": ("golf", "pga"), "UFC": ("mma", "ufc")},
    )
    monkeypatch.setattr(
        espn_headshot_service,
        "DETAIL_ROSTER_LEAGUES",
        {"SOCCER": ("soccer", "usa.1")},
    )
    monkeypatch.setattr(
        espn_headshot_service,
        "_fetch_team_ids",
        lambda _sport, _league: ["1"],
    )
    monkeypatch.setattr(
        espn_headshot_service,
        "_fetch_team_roster",
        lambda _sport, _league, _team: {
            "a ja wilson": "https://cdn.example/wilson.png"
        },
    )
    monkeypatch.setattr(
        espn_headshot_service,
        "_fetch_event_athletes",
        lambda sport, _league: {
            ("rory mcilroy" if sport == "golf" else "jose aldo"):
            f"https://cdn.example/{sport}.png"
        },
    )
    monkeypatch.setattr(
        espn_headshot_service,
        "_fetch_detail_roster_athletes",
        lambda _sport, _league: {
            "miguel almiron": "https://cdn.example/almiron.png"
        },
    )

    counts = espn_headshot_service.refresh_espn_headshot_map()

    assert counts == {"NBA": 1, "PGA": 1, "UFC": 1, "SOCCER": 1}
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert set(payload["leagues"]) == {"NBA", "PGA", "UFC", "SOCCER"}


def test_var_data_espn_cache_reports_persistent_mode(monkeypatch):
    _use_map(monkeypatch, Path("/var/data/espn_headshot_map.json"))

    health = espn_headshot_service.espn_headshot_cache_health()

    assert health["mode"] == "persistent-disk"


def test_espn_detail_roster_hydrates_unique_athletes(monkeypatch):
    monkeypatch.setattr(
        espn_headshot_service,
        "_fetch_team_ids",
        lambda _sport, _league: ["1", "2"],
    )
    monkeypatch.setattr(
        espn_headshot_service,
        "_fetch_roster_athlete_ids",
        lambda _sport, _league, team: (
            {"10", "20"} if team == "1" else {"20", "30"}
        ),
    )
    captured = {}

    def fake_hydrate(sport, league, athlete_ids):
        captured.update(sport=sport, league=league, athlete_ids=athlete_ids)
        return {"miguel almiron": "https://cdn.example/almiron.png"}

    monkeypatch.setattr(
        espn_headshot_service,
        "_hydrate_athlete_headshots",
        fake_hydrate,
    )

    players = espn_headshot_service._fetch_detail_roster_athletes(
        "soccer",
        "usa.1",
    )

    assert players == {
        "miguel almiron": "https://cdn.example/almiron.png"
    }
    assert captured == {
        "sport": "soccer",
        "league": "usa.1",
        "athlete_ids": {"10", "20", "30"},
    }
