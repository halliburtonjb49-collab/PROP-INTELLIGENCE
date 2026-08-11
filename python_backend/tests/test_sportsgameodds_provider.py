from pathlib import Path

from database.cache import PropCache
from providers import sportsgameodds
from services.prop_processor import process_and_cache_props


def _reset_usage() -> None:
    sportsgameodds._usage.update(
        {
            "configured": True,
            "requests": 0,
            "lastResponseAt": None,
            "lastStatus": None,
            "lastError": None,
            "rateLimitedResponses": 0,
            "consecutiveRateLimits": 0,
            "cooldownUntil": None,
        }
    )


def _event() -> dict[str, object]:
    return {
        "eventID": "NBA_LAL_BOS_2026",
        "leagueID": "NBA",
        "status": {
            "startsAt": "2026-07-28T00:00:00Z",
            "started": False,
            "ended": False,
            "finalized": False,
        },
        "teams": {
            "home": {"name": "Boston Celtics"},
            "away": {"name": "Los Angeles Lakers"},
        },
        "players": {
            "LEBRON_JAMES_1_NBA": {
                "playerID": "LEBRON_JAMES_1_NBA",
                "name": "LeBron James",
            }
        },
        "odds": {
            "points-LEBRON_JAMES_1_NBA-game-ou-over": {
                "statID": "points",
                "statEntityID": "LEBRON_JAMES_1_NBA",
                "playerID": "LEBRON_JAMES_1_NBA",
                "periodID": "game",
                "betTypeID": "ou",
                "sideID": "over",
                "bookOverUnder": "24.5",
                "byBookmaker": {
                    "draftkings": {
                        "odds": "-110",
                        "overUnder": "24.5",
                        "available": True,
                    },
                    "fanduel": {
                        "odds": "-105",
                        "overUnder": "24.5",
                        "available": True,
                    },
                },
            },
            "points-LEBRON_JAMES_1_NBA-game-ou-under": {
                "statID": "points",
                "statEntityID": "LEBRON_JAMES_1_NBA",
                "playerID": "LEBRON_JAMES_1_NBA",
                "periodID": "game",
                "betTypeID": "ou",
                "sideID": "under",
                "bookOverUnder": "24.5",
                "byBookmaker": {
                    "draftkings": {
                        "odds": "-110",
                        "overUnder": "24.5",
                        "available": True,
                    },
                    "fanduel": {
                        "odds": "-115",
                        "overUnder": "24.5",
                        "available": True,
                    },
                },
            },
        },
    }


def test_normalizes_player_props_into_existing_ingestion_shape() -> None:
    event, payload = sportsgameodds.normalize_event(
        _event(),
        sport_key="basketball_nba",
    )
    assert event["id"] == "sgo:NBA_LAL_BOS_2026"
    assert event["home_team"] == "Boston Celtics"
    assert event["away_team"] == "Los Angeles Lakers"
    assert len(payload["bookmakers"]) == 2
    draftkings = next(
        book for book in payload["bookmakers"] if book["key"] == "draftkings"
    )
    market = draftkings["markets"][0]
    assert market["key"] == "player_points"
    assert {row["name"] for row in market["outcomes"]} == {"Over", "Under"}
    assert all(row["description"] == "LeBron James" for row in market["outcomes"])


def test_normalized_payload_runs_through_real_prop_processor(tmp_path: Path) -> None:
    cache = PropCache(tmp_path / "props.db")
    event, payload = sportsgameodds.normalize_event(
        _event(),
        sport_key="basketball_nba",
    )
    inserted = process_and_cache_props(
        cache=cache,
        sport_key="basketball_nba",
        event=event,
        odds_payload=payload,
    )
    rows = cache.load_props()
    assert inserted == 2
    assert len(rows) == 2
    assert {row["bookmaker"] for row in rows} == {"DRAFTKINGS", "FANDUEL"}
    assert all(row["over_odds"] is not None for row in rows)
    assert all(row["under_odds"] is not None for row in rows)


def test_pagination_passes_opaque_cursor(monkeypatch) -> None:
    calls: list[dict[str, object]] = []

    def fake_get(_path: str, params: dict[str, object]):
        calls.append(params)
        if len(calls) == 1:
            return {"success": True, "data": [{"eventID": "one"}], "nextCursor": "opaque"}
        return {"success": True, "data": [{"eventID": "two"}]}

    monkeypatch.setattr(sportsgameodds, "_get", fake_get)
    events = sportsgameodds.fetch_upcoming_events("NBA", max_pages=3)
    assert [event["eventID"] for event in events] == ["one", "two"]
    assert calls[1]["cursor"] == "opaque"


def test_primary_pruning_preserves_supplemental_namespace(tmp_path: Path) -> None:
    cache = PropCache(tmp_path / "props.db")
    cache.replace_games(
        "basketball_nba",
        [
            {"id": "primary", "home_team": "A", "away_team": "B"},
            {"id": "sgo:backup", "home_team": "A", "away_team": "B"},
        ],
    )
    cache.prune_sport_to_event_ids(
        sport="basketball_nba",
        active_event_ids=["primary"],
    )
    with cache.connect() as connection:
        ids = {row["id"] for row in connection.execute("select id from games")}
    assert ids == {"primary", "sgo:backup"}


def test_429_starts_cooldown_and_blocks_followup_network_call(monkeypatch) -> None:
    class FakeResponse:
        status_code = 429
        headers = {"Retry-After": "120"}

    class FakeSession:
        calls = 0

        def get(self, *_args, **_kwargs):
            self.calls += 1
            return FakeResponse()

    _reset_usage()
    session = FakeSession()
    monkeypatch.setattr(sportsgameodds, "SPORTSGAMEODDS_API_KEY", "test-key")
    monkeypatch.setattr(sportsgameodds, "_session", lambda: session)
    monkeypatch.setattr(sportsgameodds, "SPORTSGAMEODDS_API_KEY_SECONDARY", "")

    try:
        sportsgameodds._get("events", {})
    except sportsgameodds.ProviderCooldownError:
        pass
    else:
        raise AssertionError("Expected provider cooldown")

    snapshot = sportsgameodds.usage_snapshot()
    assert snapshot["lastStatus"] == 429
    assert snapshot["coolingDown"] is True
    assert snapshot["retryAfterSeconds"] > 0
    assert snapshot["rateLimitedResponses"] == 1

    try:
        sportsgameodds._get("events", {})
    except sportsgameodds.ProviderCooldownError:
        pass
    else:
        raise AssertionError("Expected active cooldown")
    assert session.calls == 1
    _reset_usage()


def test_rejected_primary_credential_uses_secondary(monkeypatch) -> None:
    class FakeResponse:
        headers = {}
        text = ""
        url = "https://api.sportsgameodds.com/v2/events"

        def __init__(self, status_code: int) -> None:
            self.status_code = status_code

        def json(self):
            return {"success": True, "data": []}

    class FakeSession:
        def __init__(self) -> None:
            self.keys: list[str] = []

        def get(self, *_args, **kwargs):
            self.keys.append(kwargs["headers"]["x-api-key"])
            return FakeResponse(401 if len(self.keys) == 1 else 200)

    _reset_usage()
    session = FakeSession()
    monkeypatch.setattr(sportsgameodds, "SPORTSGAMEODDS_API_KEY", "bad-primary")
    monkeypatch.setattr(
        sportsgameodds,
        "SPORTSGAMEODDS_API_KEY_SECONDARY",
        "working-secondary",
    )
    monkeypatch.setattr(sportsgameodds, "_session", lambda: session)

    payload = sportsgameodds._get("events", {})

    assert payload["success"] is True
    assert session.keys == ["bad-primary", "working-secondary"]
    snapshot = sportsgameodds.usage_snapshot()
    assert snapshot["requests"] == 2
    assert snapshot["lastStatus"] == 200
    assert snapshot["coolingDown"] is False
    _reset_usage()
