from datetime import datetime, timezone

from services import sportradar_pregame_service as service


def test_basketball_summary_captures_starters_bench_and_inactives():
    payload = {
        "home": {
            "alias": "MIN",
            "players": [
                {"id": "1", "full_name": "Starter One", "active": True, "starter": True, "primary_position": "G"},
                {"id": "2", "full_name": "Bench Two", "active": True, "starter": False, "primary_position": "F"},
                {"id": "3", "full_name": "Inactive Three", "active": False, "not_playing_reason": "Inactive - Injury"},
            ],
        },
        "away": {"alias": "NY"},
    }
    rows = service.normalize_basketball_summary(payload, sport="WNBA", event_id="g1", event_time="2026-08-11T23:00:00Z")
    assert [row["status"] for row in rows] == ["CONFIRMED_STARTER", "BENCH", "INACTIVE"]
    assert all(row["confirmed"] for row in rows)
    assert rows[0]["opponent"] == "NY"


def test_nfl_roster_captures_game_day_statuses():
    payload = {
        "home": {
            "alias": "CHI",
            "players": [
                {"id": "1", "full_name": "Starting Quarterback", "position": "QB", "in_game_status": "started"},
                {"id": "2", "full_name": "Active Receiver", "position": "WR", "in_game_status": "active"},
                {"id": "3", "full_name": "Inactive Runner", "position": "RB", "in_game_status": "deactivated"},
            ],
        },
        "away": {"alias": "GB"},
    }
    rows = service.normalize_nfl_roster(payload, event_id="n1", event_time="2026-08-11T23:00:00Z")
    assert [row["status"] for row in rows] == ["CONFIRMED_STARTER", "CONFIRMED_ACTIVE", "INACTIVE"]
    assert rows[0]["payload"]["position"] == "QB"


def test_nhl_summary_captures_goalie_and_scratches():
    payload = {
        "home": {
            "alias": "DAL",
            "players": [
                {"id": "1", "full_name": "Goalie One", "primary_position": "G", "starter": True, "played": True},
                {"id": "2", "full_name": "Scratch Two", "primary_position": "F", "scratched": True},
            ],
        },
        "away": {"alias": "COL"},
    }
    rows = service.normalize_nhl_summary(payload, event_id="h1", event_time="2026-10-11T23:00:00Z")
    assert rows[0]["status"] == "CONFIRMED_STARTER"
    assert rows[0]["payload"]["role"] == "STARTING_GOALIE"
    assert rows[1]["status"] == "SCRATCHED"


def test_soccer_lineups_capture_xi_substitutes_and_formation():
    payload = {
        "sport_event_conditions": {"lineups": {"confirmed": True}},
        "lineups": [
            {
                "competitor": {"name": "Arsenal", "abbreviation": "ARS"},
                "formation": {"type": "4-3-3"},
                "players": [
                    {"id": "1", "name": "Starter One", "starter": True, "position": "striker"},
                    {"id": "2", "name": "Sub Two", "starter": False, "position": "midfielder"},
                ],
            },
            {"competitor": {"name": "Chelsea", "abbreviation": "CHE"}, "players": []},
        ],
    }
    rows = service.normalize_soccer_lineups(payload, event_id="s1", event_time="2026-08-11T19:00:00Z")
    assert rows[0]["status"] == "STARTING_XI"
    assert rows[1]["status"] == "SUBSTITUTE"
    formation = next(row for row in rows if row["player_name"] == "Arsenal formation")
    assert formation["payload"]["formation"] == "4-3-3"
    assert formation["confirmed"] is True


def test_soccer_filter_only_keeps_supported_board_leagues():
    premier_league = {
        "sport_event_context": {"competition": {"name": "Premier League"}}
    }
    champions_league = {
        "sport_event_context": {"competition": {"name": "UEFA Champions League"}}
    }
    assert service._supported_soccer_event(premier_league)
    assert not service._supported_soccer_event(champions_league)


def test_string_false_does_not_confirm_soccer_lineup():
    payload = {
        "sport_event_conditions": {"lineups": {"confirmed": "false"}},
        "lineups": [{
            "competitor": {"name": "Arsenal"},
            "players": [{"name": "Starter One", "starter": True}],
        }],
    }
    rows = service.normalize_soccer_lineups(
        payload, event_id="s2", event_time="2026-08-11T19:00:00Z"
    )
    assert rows[0]["confirmed"] is False

def test_window_is_limited_to_pregame_period():
    now = datetime(2026, 8, 11, 12, tzinfo=timezone.utc)
    assert service._inside_window("2026-08-11T13:00:00Z", before_seconds=7200, now=now)
    assert not service._inside_window("2026-08-11T15:00:00Z", before_seconds=7200, now=now)
    assert not service._inside_window("bad", before_seconds=7200, now=now)


def test_empty_schedule_is_cached_for_four_hours(monkeypatch):
    writes = []
    monkeypatch.setattr(service, "get_json", lambda _key: None)
    monkeypatch.setattr(service, "_request_json", lambda _url: {"games": []})
    monkeypatch.setattr(service, "set_json", lambda key, value, ttl_seconds: writes.append((key, value, ttl_seconds)))
    assert service._cached_json("key", "url") == {"games": []}
    assert writes[0][2] == 14_400


def test_unlicensed_sport_is_skipped_not_failed(monkeypatch):
    monkeypatch.setattr(service, "SPORTRADAR_API_KEY", "configured")
    monkeypatch.setattr(service, "SPORTRADAR_WNBA_API_KEY", "configured")
    monkeypatch.setattr(service, "_sync_scheduled_summaries", lambda **_kwargs: (_ for _ in ()).throw(service.NotEntitledError("not entitled (403)")))
    monkeypatch.setattr(service, "_sync_nfl", lambda _persist: {"provider": "nfl", "created": 0})
    monkeypatch.setattr(service, "_sync_soccer", lambda _target, _persist: {"provider": "soccer", "created": 0})
    results = service.sync_sportradar_pregame(lambda _provider, _rows: 0)
    assert results[0]["skipped"] == "not entitled (403)"
    assert "error" not in results[0]


def test_missing_key_skips_all_requests(monkeypatch):
    monkeypatch.setattr(service, "SPORTRADAR_API_KEY", "")
    result = service.sync_sportradar_pregame(lambda _provider, _rows: 0)
    assert result == [{"provider": "sportradar-pregame", "created": 0, "skipped": "not configured"}]
