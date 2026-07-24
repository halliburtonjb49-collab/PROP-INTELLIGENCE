import json
from pathlib import Path

import pytest

from services import sportmonks_headshot_service


class _Response:
    ok = True

    @staticmethod
    def json():
        return {"data": []}


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
        "leagueCounts": {},
        "leagueTeamCounts": {},
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


def test_sportmonks_uses_raw_token_in_authorization_header(monkeypatch):
    request = {}

    def fake_get(url, **kwargs):
        request.update(url=url, **kwargs)
        return _Response()

    monkeypatch.setattr(
        sportmonks_headshot_service,
        "SPORTMONKS_API_KEY",
        "token-value",
    )
    monkeypatch.setattr(sportmonks_headshot_service.requests, "get", fake_get)

    assert sportmonks_headshot_service._get("/leagues") == {"data": []}
    assert request["headers"] == {"Authorization": "token-value"}
    assert "api_token" not in request["params"]


def test_sportmonks_collection_fetches_every_page(monkeypatch):
    pages = []

    def fake_get(_path, **params):
        pages.append(params)
        return {
            "data": [{"id": params["page"]}],
            "pagination": {"has_more": params["page"] == 1},
        }

    monkeypatch.setattr(sportmonks_headshot_service, "_get", fake_get)

    assert sportmonks_headshot_service._get_all("/leagues") == [
        {"id": 1},
        {"id": 2},
    ]
    assert pages == [
        {"page": 1, "per_page": 50},
        {"page": 2, "per_page": 50},
    ]


def test_sportmonks_refresh_rejects_missing_subscription_leagues(monkeypatch):
    monkeypatch.setattr(sportmonks_headshot_service, "SPORTMONKS_API_KEY", "token")
    monkeypatch.setattr(
        sportmonks_headshot_service,
        "_find_target_season_ids",
        lambda: {},
    )

    with pytest.raises(RuntimeError, match="subscription includes"):
        sportmonks_headshot_service.refresh_sportmonks_headshot_map()


def test_sportmonks_reads_lowercase_currentseason_relation(monkeypatch):
    monkeypatch.setattr(
        sportmonks_headshot_service,
        "_get_all",
        lambda _path, **_params: [
            {
                "id": 8,
                "name": "Premier League",
                "country": {"name": "United Kingdom"},
                "currentseason": {"id": 25583},
            }
        ],
    )

    assert sportmonks_headshot_service._find_target_season_ids() == {
        "soccer_epl": 25583
    }


def test_sportmonks_extended_squad_reads_direct_player_shape(monkeypatch):
    monkeypatch.setattr(
        sportmonks_headshot_service,
        "_get",
        lambda _path, **_params: {
            "data": [
                {
                    "name": "Lionel Messi",
                    "image_path": "https://cdn.example/messi.png",
                }
            ]
        },
    )

    assert sportmonks_headshot_service._fetch_extended_team_photos(239235) == {
        "lionel messi": "https://cdn.example/messi.png"
    }


def test_sportmonks_team_ids_fall_back_to_season_teams(monkeypatch):
    monkeypatch.setattr(
        sportmonks_headshot_service,
        "_get_all",
        lambda _path, **_params: [],
    )
    monkeypatch.setattr(
        sportmonks_headshot_service,
        "_get",
        lambda path, **params: {
            "data": {
                "id": 25593,
                "teams": [{"id": 239235}, {"id": 413}],
            }
        },
    )

    assert sportmonks_headshot_service._fetch_team_ids(25593) == [
        239235,
        413,
    ]


def test_sportmonks_team_ids_fall_back_to_fixture_participants(monkeypatch):
    calls = []

    def fake_get_all(path, **params):
        calls.append((path, params))
        if path.startswith("/fixtures/"):
            return [
                {
                    "participants": [
                        {"id": 239235, "name": "Inter Miami"},
                        {"id": 413, "name": "LA Galaxy"},
                    ]
                },
                {
                    "participants": [
                        {"id": 413, "name": "LA Galaxy"},
                        {"id": 111, "name": "Austin FC"},
                    ]
                },
            ]
        return []

    monkeypatch.setattr(sportmonks_headshot_service, "_get_all", fake_get_all)
    monkeypatch.setattr(
        sportmonks_headshot_service,
        "_get",
        lambda _path, **_params: {"data": {"teams": []}},
    )

    assert sportmonks_headshot_service._fetch_team_ids(25593) == [
        111,
        413,
        239235,
    ]
    assert calls[-1] == (
        "/fixtures/seasons/25593",
        {"include": "participants"},
    )
