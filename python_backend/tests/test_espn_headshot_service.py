import json
from datetime import datetime, timezone
from pathlib import Path

from services import espn_headshot_service


def _use_map(monkeypatch, path):
    monkeypatch.setattr(espn_headshot_service, "HEADSHOT_MAP_PATH", path)
    monkeypatch.setattr(espn_headshot_service, "_BUNDLED_MAP_PATH", path)
    monkeypatch.setattr(espn_headshot_service, "SOCCER_DETAIL_LEAGUES", ())
    # Release checks may run on a developer machine that has a production
    # Redis URL configured. Unit tests must never contact that live cache or
    # stall behind its network timeout.
    monkeypatch.setattr(
        espn_headshot_service,
        "get_distributed_json",
        lambda _key: None,
    )
    monkeypatch.setattr(
        espn_headshot_service,
        "set_distributed_json",
        lambda _key, _payload, **_kwargs: True,
    )
    espn_headshot_service._load_map.cache_clear()


def test_default_team_leagues_include_nfl_headshots():
    assert espn_headshot_service.LEAGUES["NFL"] == ("football", "nfl")


def test_replacement_sports_are_included_without_removed_specialty_sports():
    assert espn_headshot_service.LEAGUES["NCAAF"] == (
        "football",
        "college-football",
    )
    assert espn_headshot_service.LEAGUES["NCAAB"] == (
        "basketball",
        "mens-college-basketball",
    )
    assert espn_headshot_service.DETAIL_ROSTER_LEAGUES["CFL"] == (
        "football",
        "cfl",
    )
    assert "PGA" not in espn_headshot_service.EVENT_LEAGUES
    assert "UFC" not in espn_headshot_service.EVENT_LEAGUES


def test_espn_cache_ignores_retired_specialty_sports(monkeypatch, tmp_path):
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

    assert "PGA" not in espn_headshot_service.EVENT_LEAGUES
    assert "UFC" not in espn_headshot_service.EVENT_LEAGUES


def test_espn_cache_reports_missed_daily_refresh(monkeypatch, tmp_path):
    path = tmp_path / "espn_headshot_map.json"
    path.write_text(
        json.dumps({
            "updatedAtUtc": "2026-08-15T09:15:00+00:00",
            "leagues": {
                "WNBA": {"player": "https://cdn.example/player.png"},
            },
        }),
        encoding="utf-8",
    )
    _use_map(monkeypatch, path)

    health = espn_headshot_service.espn_headshot_cache_health(
        now=datetime(2026, 8, 16, 12, 0, tzinfo=timezone.utc),
    )

    assert health["status"] == "ok"
    assert health["stale"] is True
    assert health["ageHours"] == 26.8


def test_espn_player_id_is_recovered_from_cached_headshot(monkeypatch, tmp_path):
    path = tmp_path / "espn_headshot_map.json"
    path.write_text(
        json.dumps(
            {
                "leagues": {
                    "SOCCER": {
                        "example player": (
                            "https://a.espncdn.com/i/headshots/soccer/"
                            "players/full/232755.png"
                        )
                    }
                }
            }
        ),
        encoding="utf-8",
    )
    _use_map(monkeypatch, path)

    assert espn_headshot_service.espn_player_id(
        "Example Player",
        "SOCCER",
    ) == "232755"


def test_espn_cache_reads_shared_redis_payload(monkeypatch, tmp_path):
    _use_map(monkeypatch, tmp_path / "missing.json")
    monkeypatch.setattr(
        espn_headshot_service,
        "get_distributed_json",
        lambda _key: {
            "updatedAtUtc": "2026-07-29T20:00:00+00:00",
            "leagues": {
                "PGA": {"rory mcilroy": "https://cdn.example/rory.png"}
            },
        },
    )

    assert (
        espn_headshot_service.espn_headshot_url("Rory McIlroy", "PGA")
        == "https://cdn.example/rory.png"
    )
    health = espn_headshot_service.espn_headshot_cache_health()
    assert health["status"] == "ok"
    assert health["mode"] == "redis"
    assert health["playerCount"] == 1


def test_espn_cache_merges_bundled_nfl_with_older_redis(monkeypatch, tmp_path):
    bundled = tmp_path / "bundled.json"
    runtime = tmp_path / "runtime.json"
    bundled.write_text(
        json.dumps(
            {
                "leagues": {
                    "NFL": {"josh allen": "https://cdn.example/allen.png"}
                }
            }
        ),
        encoding="utf-8",
    )
    runtime.write_text(
        json.dumps(
            {
                "leagues": {
                    "NBA": {"a ja wilson": "https://cdn.example/wilson.png"}
                }
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(espn_headshot_service, "_BUNDLED_MAP_PATH", bundled)
    monkeypatch.setattr(espn_headshot_service, "HEADSHOT_MAP_PATH", runtime)
    monkeypatch.setattr(
        espn_headshot_service,
        "get_distributed_json",
        lambda _key: {
            "leagues": {
                "NHL": {"sidney crosby": "https://cdn.example/crosby.png"}
            }
        },
    )
    espn_headshot_service._load_map.cache_clear()

    assert espn_headshot_service.espn_headshot_url("Josh Allen", "NFL")
    assert espn_headshot_service.espn_headshot_url("A'ja Wilson", "NBA")
    assert espn_headshot_service.espn_headshot_url("Sidney Crosby", "NHL")


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
        {},
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

    assert counts == {"NBA": 1, "SOCCER": 1}
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert set(payload["leagues"]) == {"NBA", "SOCCER"}


def test_partial_refresh_preserves_last_known_good_players(monkeypatch, tmp_path):
    path = tmp_path / "espn_headshot_map.json"
    path.write_text(
        json.dumps({
            "leagues": {
                "WNBA": {
                    "existing player": "https://cdn.example/existing.png",
                }
            }
        }),
        encoding="utf-8",
    )
    _use_map(monkeypatch, path)
    monkeypatch.setattr(
        espn_headshot_service,
        "LEAGUES",
        {"WNBA": ("basketball", "wnba")},
    )
    monkeypatch.setattr(espn_headshot_service, "EVENT_LEAGUES", {})
    monkeypatch.setattr(espn_headshot_service, "DETAIL_ROSTER_LEAGUES", {})
    monkeypatch.setattr(
        espn_headshot_service,
        "_fetch_league_roster_headshots",
        lambda *_args: {
            "new player": "https://cdn.example/new.png",
        },
    )

    counts = espn_headshot_service.refresh_espn_headshot_map()

    assert counts["WNBA"] == 2
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload["leagues"]["WNBA"] == {
        "existing player": "https://cdn.example/existing.png",
        "new player": "https://cdn.example/new.png",
    }


def test_var_data_espn_cache_reports_persistent_mode(monkeypatch):
    monkeypatch.setattr(
        espn_headshot_service,
        "_BUNDLED_MAP_PATH",
        Path("/var/data/espn_headshot_map.json"),
    )
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
