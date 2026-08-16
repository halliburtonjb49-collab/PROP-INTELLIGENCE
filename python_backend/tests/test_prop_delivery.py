from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor
from threading import Lock
import time

from fastapi.testclient import TestClient
import pytest

import main
from services.prop_service import _make_prop_id


@pytest.fixture(autouse=True)
def authenticated_prop_feed():
    main.app.dependency_overrides[main.require_user_id] = lambda: "test-user"
    with main._prop_response_cache_lock:
        main._prop_response_cache.clear()
    yield
    main.app.dependency_overrides.pop(main.require_user_id, None)
    with main._prop_response_cache_lock:
        main._prop_response_cache.clear()


@dataclass
class FakeProp:
    id: str
    player: str
    sport: str
    sportsbook: str
    category: str
    market: str = "Hits"
    matchup: str = "Away @ Home"
    recommendedSide: str = "OVER"
    tier: str = "Premium"
    confidence: int = 70
    edge: float = 8.0
    evPercentage: float | None = None
    fairProbability: float | None = None
    isPositiveEv: bool = False
    startTimeUtc: str = "2099-07-20T20:00:00Z"
    lastUpdatedUtc: str = "2099-07-20T19:55:00Z"
    dataStale: bool = False

    def model_dump(self) -> dict[str, object]:
        return self.__dict__.copy()


def test_production_cors_preflight_is_allowed() -> None:
    response = TestClient(main.app).options(
        "/api/props",
        headers={
            "Origin": "https://app.propsintell.com",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "https://app.propsintell.com"


def test_player_images_are_served_with_browser_cache_headers() -> None:
    response = TestClient(main.app).get("/player-images/aaron_judge.png")
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert "max-age=604800" in response.headers["cache-control"]


def test_missing_player_image_returns_not_found() -> None:
    response = TestClient(main.app).get("/player-images/does_not_exist.png")
    assert response.status_code == 404


def test_prop_feed_repairs_missing_image_from_current_headshot_cache(
    monkeypatch,
) -> None:
    row = FakeProp(
        "wnba-photo", "Breanna Stewart", "WNBA", "FANDUEL", "POINTS"
    )
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [row])
    monkeypatch.setattr(
        main,
        "resolve_player_image",
        lambda player, sport: (
            "https://a.espncdn.com/i/headshots/wnba/players/full/2998928.png"
        ),
    )

    response = TestClient(main.app).get("/api/props")

    assert response.status_code == 200
    assert response.json()["props"][0]["imagePath"] == (
        "https://a.espncdn.com/i/headshots/wnba/players/full/2998928.png"
    )



def test_player_image_proxy_rejects_unapproved_hosts() -> None:
    response = TestClient(main.app).get(
        "/player-image-proxy",
        params={"url": "https://example.com/player.png"},
    )
    assert response.status_code == 400


def test_player_image_proxy_retries_and_returns_cacheable_image(monkeypatch) -> None:
    class Upstream:
        status_code = 200
        is_redirect = False
        content = b"\x89PNG\r\n\x1a\n"
        headers = {"content-type": "image/png"}

    attempts = 0

    def fake_get(*args, **kwargs):
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise main.requests.ConnectionError("temporary")
        return Upstream()

    monkeypatch.setattr(main.requests, "get", fake_get)
    response = TestClient(main.app).get(
        "/player-image-proxy",
        params={"url": "https://a.espncdn.com/i/headshots/nba/players/full/1.png"},
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert "max-age=604800" in response.headers["cache-control"]
    assert attempts == 2


def test_prop_page_filters_server_side_and_exposes_version(monkeypatch) -> None:
    rows = [
        FakeProp("pp-mlb", "One", "MLB", "PRIZEPICKS", "HITS"),
        FakeProp("fd-mlb", "Two", "MLB", "FANDUEL", "HITS"),
        FakeProp("pp-nfl", "Three", "NFL", "PRIZEPICKS", "RECEPTIONS"),
    ]
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)
    response = TestClient(main.app).get(
        "/api/props",
        params={
            "sportsbook": "PRIZEPICKS",
            "sport": "MLB",
            "category": "HITS",
            "search": "One",
            "limit": 75,
        },
    )
    payload = response.json()
    assert response.status_code == 200
    assert payload["count"] == 1
    assert payload["facetCount"] == 1
    assert payload["categoryCounts"] == {"HITS": 1}
    assert [row["id"] for row in payload["props"]] == ["pp-mlb"]
    assert payload["version"] == main.APP_VERSION
    assert response.headers["etag"]
    assert response.headers["cache-control"] == "private, no-store, max-age=0"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"
    assert int(response.headers["x-ratelimit-limit"]) > 0


def test_verdict_filter_is_applied_before_pagination(monkeypatch) -> None:
    passed = FakeProp("pass", "Passed", "MLB", "FANDUEL", "HITS")
    passed.verdict = {"decision": "PASS", "actionable": False}
    lean = FakeProp("lean", "Lean", "MLB", "FANDUEL", "HITS")
    lean.verdict = {"decision": "LEAN", "actionable": True}
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [passed, lean])

    response = TestClient(main.app).get(
        "/api/props",
        params={"verdict": "LEAN", "limit": 1},
    )

    assert response.status_code == 200
    assert response.json()["count"] == 1
    assert [row["id"] for row in response.json()["props"]] == ["lean"]
    assert response.json()["filters"]["verdict"] == "LEAN"


def test_playable_filter_returns_every_actionable_verdict(monkeypatch) -> None:
    rows = []
    for decision, actionable in (
        ("PASS", False),
        ("WAIT", False),
        ("LEAN", True),
        ("SHOP", True),
        ("PLAY_NOW", True),
    ):
        prop = FakeProp(decision.lower(), decision, "MLB", "FANDUEL", "HITS")
        prop.verdict = {"decision": decision, "actionable": actionable}
        rows.append(prop)
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)

    response = TestClient(main.app).get(
        "/api/props",
        params={"verdict": "ACTIONABLE", "limit": 2},
    )

    assert response.status_code == 200
    assert response.json()["count"] == 3
    assert len(response.json()["props"]) == 2
    assert all(row["verdict"]["actionable"] for row in response.json()["props"])
    assert response.json()["verdictCounts"] == {
        "ACTIONABLE": 3,
        "ALL": 5,
        "LEAN": 1,
        "PASS": 1,
        "PLAY_NOW": 1,
        "SHOP": 1,
        "WAIT": 1,
    }
    assert response.json()["totalCategoryCounts"] == {"HITS": 5}
    assert response.json()["playableCategoryCounts"] == {"HITS": 3}
    assert response.json()["totalSportCategoryCounts"] == {
        "MLB": {"HITS": 5}
    }
    assert response.json()["playableSportCategoryCounts"] == {
        "MLB": {"HITS": 3}
    }

def test_prop_id_stays_stable_when_site_line_changes() -> None:
    before = _make_prop_id("event-1", "Player One", "points", 20.5, "FanDuel")
    after = _make_prop_id("event-1", "Player One", "points", 21.5, "FanDuel")

    assert before == after


def test_prop_page_can_return_only_lines_that_moved(monkeypatch) -> None:
    unchanged = FakeProp("unchanged", "One", "NBA", "FANDUEL", "POINTS")
    unchanged.openingLine = 20.5
    unchanged.currentLine = 20.5
    moved = FakeProp("moved", "Two", "NBA", "FANDUEL", "POINTS")
    moved.openingLine = 20.5
    moved.currentLine = 21.5
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [unchanged, moved])

    response = TestClient(main.app).get(
        "/api/props",
        params={"sport": "NBA", "onlyMoved": True},
    )

    assert response.status_code == 200
    assert response.json()["count"] == 1
    assert [row["id"] for row in response.json()["props"]] == ["moved"]


def test_all_sports_feed_places_soccer_after_other_sports(monkeypatch) -> None:
    rows = [
        FakeProp("soccer", "Soccer Star", "SOCCER", "FANDUEL", "SHOTS"),
        FakeProp("nba", "Basketball Star", "NBA", "FANDUEL", "POINTS"),
    ]
    rows[0].confidence = 99
    rows[1].confidence = 60
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)

    response = TestClient(main.app).get(
        "/api/props",
        params={"sport": "All", "sortBy": "confidence"},
    )

    assert response.status_code == 200
    assert [row["id"] for row in response.json()["props"]] == ["nba", "soccer"]


def test_prop_feed_requires_a_valid_user_session() -> None:
    main.app.dependency_overrides.pop(main.require_user_id, None)
    main.app.dependency_overrides.pop(main.require_core, None)
    response = TestClient(main.app).get("/api/props")
    assert response.status_code == 401
    assert "no-store" in response.headers["cache-control"]


def test_prop_readiness_exposes_metadata_without_authentication(monkeypatch) -> None:
    rows = [
        FakeProp("hits", "One", "MLB", "FANDUEL", "HITS"),
        FakeProp("ks", "Two", "MLB", "FANDUEL", "STRIKEOUTS"),
    ]
    rows[0].lastUpdatedUtc = "2026-07-29T12:00:00Z"
    rows[1].lastUpdatedUtc = "2026-07-29T12:05:00Z"
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)
    main.app.dependency_overrides.pop(main.require_user_id, None)

    response = TestClient(main.app).get("/api/props/readiness")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "count": 2,
        "lastDataUpdatedAt": "2026-07-29T12:05:00Z",
        "version": main.APP_VERSION,
        "responseMs": response.json()["responseMs"],
        "dataProtected": True,
    }
    assert "no-store" in response.headers["cache-control"]


def test_prop_readiness_uses_compact_distributed_summary(monkeypatch) -> None:
    monkeypatch.setattr(
        main,
        "get_distributed_json",
        lambda key: {
            "count": 8489,
            "lastDataUpdatedAt": "2026-07-29T16:26:39Z",
            "version": "catalog-v1",
        }
        if key == main._PROP_CATALOG_SUMMARY_KEY
        else None,
    )
    monkeypatch.setattr(
        main,
        "_cached_prop_catalog",
        lambda: pytest.fail("readiness loaded the full prop catalog"),
    )
    main.app.dependency_overrides.pop(main.require_user_id, None)

    response = TestClient(main.app).get("/api/props/readiness")

    assert response.status_code == 200
    assert response.json()["count"] == 8489
    assert response.json()["lastDataUpdatedAt"] == "2026-07-29T16:26:39Z"


def test_prop_readiness_can_use_compact_catalog_version(monkeypatch) -> None:
    def fake_get(key: str):
        if key == main._PROP_CATALOG_VERSION_KEY:
            return (
                "commit-sha:2026-07-29T16:26:39.035904+00:00:8489"
            )
        return None

    monkeypatch.setattr(main, "get_distributed_json", fake_get)
    monkeypatch.setattr(
        main,
        "_cached_prop_catalog",
        lambda: pytest.fail("readiness loaded the full prop catalog"),
    )
    main.app.dependency_overrides.pop(main.require_user_id, None)

    response = TestClient(main.app).get("/api/props/readiness")

    assert response.status_code == 200
    assert response.json()["count"] == 8489
    assert (
        response.json()["lastDataUpdatedAt"]
        == "2026-07-29T16:26:39.035904+00:00"
    )


def test_category_facets_are_not_reduced_by_selected_category(monkeypatch) -> None:
    rows = [
        FakeProp("hits", "One", "MLB", "FANDUEL", "HITS"),
        FakeProp("ks", "Two", "MLB", "FANDUEL", "STRIKEOUTS"),
    ]
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)
    response = TestClient(main.app).get(
        "/api/props",
        params={"sportsbook": "FANDUEL", "category": "HITS", "limit": 75},
    )
    payload = response.json()
    assert payload["count"] == 1
    assert payload["facetCount"] == 2
    assert payload["categoryCounts"] == {"HITS": 1, "STRIKEOUTS": 1}
    assert payload["sportCounts"] == {"MLB": 2}
    assert payload["sportCategoryCounts"] == {
        "MLB": {"HITS": 1, "STRIKEOUTS": 1}
    }


def test_narrow_category_can_skip_expensive_reliability_work(monkeypatch) -> None:
    rows = [
        FakeProp("reb", "One", "WNBA", "FANDUEL", "REBOUNDS"),
        FakeProp("ast", "Two", "WNBA", "FANDUEL", "ASSISTS"),
    ]
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)
    monkeypatch.setattr(
        main,
        "build_provider_reliability",
        lambda *args, **kwargs: pytest.fail(
            "narrow category request rebuilt reliability diagnostics"
        ),
    )
    monkeypatch.setattr(
        main,
        "_enqueue_prop_refresh",
        lambda: pytest.fail("narrow category request queued feed recovery"),
    )

    response = TestClient(main.app).get(
        "/api/props",
        params={
            "sport": "WNBA",
            "category": "REBOUNDS",
            "includeReliability": "false",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["count"] == 1
    assert [row["id"] for row in payload["props"]] == ["reb"]
    assert payload["categoryCounts"] == {"ASSISTS": 1, "REBOUNDS": 1}
    assert payload["providerCoverage"] == {}
    assert payload["providerReliability"] == {}

def test_site_facets_report_full_sport_and_category_totals(monkeypatch) -> None:
    rows = [
        FakeProp("mlb-hits", "One", "MLB", "PRIZEPICKS", "HITS"),
        FakeProp("mlb-ks", "Two", "MLB", "PRIZEPICKS", "STRIKEOUTS"),
        FakeProp("nfl-rec", "Three", "NFL", "PRIZEPICKS", "RECEPTIONS"),
        FakeProp("other-site", "Four", "NBA", "FANDUEL", "POINTS"),
    ]
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)

    payload = TestClient(main.app).get(
        "/api/props",
        params={"sportsbook": "PRIZEPICKS", "limit": 1},
    ).json()

    assert payload["returned"] == 1
    assert payload["sportCounts"] == {"MLB": 2, "NFL": 1}
    assert payload["sportCategoryCounts"] == {
        "MLB": {"HITS": 1, "STRIKEOUTS": 1},
        "NFL": {"RECEPTIONS": 1},
    }


def test_partial_provider_category_coverage_is_reported(monkeypatch) -> None:
    rows = [
        *[
            FakeProp(
                f"pp-{index}",
                f"PrizePicks {index}",
                "MLB",
                "PRIZEPICKS",
                "HITS + RUNS + RBIS",
            )
            for index in range(9)
        ],
        *[
            FakeProp(
                f"dk-{index}",
                f"DraftKings {index}",
                "MLB",
                "DRAFTKINGS",
                "HITS + RUNS + RBIS",
            )
            for index in range(36)
        ],
    ]
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)
    queued = []
    monkeypatch.setattr(
        main,
        "_enqueue_prop_refresh",
        lambda: queued.append(True) or {"id": "coverage-recovery"},
    )

    payload = TestClient(main.app).get(
        "/api/props",
        params={"sportsbook": "PRIZEPICKS", "sport": "MLB", "limit": 75},
    ).json()

    coverage = payload["providerCoverage"]
    assert coverage["limited"] is True
    assert coverage["selectedSite"] == "PRIZEPICKS"
    assert coverage["recovery"] == {
        "requested": True,
        "queued": True,
        "reason": "partial_provider_coverage",
        "jobId": "coverage-recovery",
    }
    assert queued == [True]
    assert coverage["issues"] == [
        {
            "sport": "MLB",
            "category": "HITS + RUNS + RBIS",
            "selectedCount": 9,
            "benchmarkCount": 36,
            "benchmarkSite": "DRAFTKINGS",
            "coverageRatio": 0.25,
        }
    ]


@pytest.mark.parametrize(
    ("site", "expected_sports", "expected_categories"),
    [
        ("PRIZEPICKS", {"MLB", "NFL"}, {"MLB": {"HITS"}, "NFL": {"RECEPTIONS"}}),
        ("UNDERDOG", {"NBA", "NHL"}, {"NBA": {"POINTS"}, "NHL": {"SHOTS"}}),
        ("FANDUEL", {"WNBA"}, {"WNBA": {"ASSISTS"}}),
        ("PICK6", {"NFL"}, {"NFL": {"PASSING YARDS"}}),
        ("DRAFTKINGS", {"MLB"}, {"MLB": {"STRIKEOUTS"}}),
        ("BETR", {"NBA"}, {"NBA": {"REBOUNDS"}}),
    ],
)
def test_each_prop_site_reports_only_its_active_sports_and_categories(
    monkeypatch,
    site: str,
    expected_sports: set[str],
    expected_categories: dict[str, set[str]],
) -> None:
    rows = [
        FakeProp("pp-mlb", "One", "MLB", "PRIZEPICKS", "HITS"),
        FakeProp("pp-nfl", "Two", "NFL", "PRIZEPICKS", "RECEPTIONS"),
        FakeProp("ud-nba", "Three", "NBA", "UNDERDOG", "POINTS"),
        FakeProp("ud-nhl", "Four", "NHL", "UNDERDOG", "SHOTS"),
        FakeProp("fd-wnba", "Five", "WNBA", "FANDUEL", "ASSISTS"),
        FakeProp("sl-nfl", "Six", "NFL", "PICK6", "PASSING YARDS"),
        FakeProp("dk-mlb", "Seven", "MLB", "DRAFTKINGS", "STRIKEOUTS"),
        FakeProp("betr-nba", "Eight", "NBA", "BETR_US_DFS", "REBOUNDS"),
    ]
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)

    payload = TestClient(main.app).get(
        "/api/props",
        params={"sportsbook": site, "limit": 75},
    ).json()

    assert set(payload["sportCounts"]) == expected_sports
    assert {
        sport: set(categories)
        for sport, categories in payload["sportCategoryCounts"].items()
    } == expected_categories


@pytest.mark.parametrize(
    ("query_site", "expected_ids"),
    [
        ("PICK 6", ["sl-nfl"]),
        ("DRAFTKINGS PICK6", ["sl-nfl"]),
        ("BETR PICKS", ["betr-nba"]),
        ("BETR-US-DFS", ["betr-nba"]),
    ],
)
def test_sportsbook_alias_queries_match_pick6_and_betr_props(
    monkeypatch,
    query_site: str,
    expected_ids: list[str],
) -> None:
    rows = [
        FakeProp("sl-nfl", "Six", "NFL", "PICK6", "PASSING YARDS"),
        FakeProp("betr-nba", "Eight", "NBA", "BETR_US_DFS", "REBOUNDS"),
        FakeProp("pp-mlb", "One", "MLB", "PRIZEPICKS", "HITS"),
    ]
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)

    payload = TestClient(main.app).get(
        "/api/props",
        params={"sportsbook": query_site, "limit": 75},
    ).json()

    assert [row["id"] for row in payload["props"]] == expected_ids


def test_started_props_are_hidden_from_the_actionable_feed(monkeypatch) -> None:
    started = FakeProp("started", "One", "MLB", "FANDUEL", "HITS")
    started.startTimeUtc = "2020-07-20T20:00:00Z"
    upcoming = FakeProp("upcoming", "Two", "MLB", "FANDUEL", "HITS")
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [started, upcoming])
    client = TestClient(main.app)

    payload = client.get("/api/props").json()
    assert [row["id"] for row in payload["props"]] == ["upcoming"]

    historical = client.get(
        "/api/props",
        params={"includePastDates": True, "includeStarted": True},
    ).json()
    assert {row["id"] for row in historical["props"]} == {"started", "upcoming"}


def test_stale_props_are_hidden_from_the_actionable_feed(monkeypatch) -> None:
    stale = FakeProp("stale", "One", "MLB", "FANDUEL", "HITS")
    stale.lastUpdatedUtc = "2020-07-20T20:00:00Z"
    fresh = FakeProp("fresh", "Two", "MLB", "FANDUEL", "HITS")
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [stale, fresh])
    client = TestClient(main.app)

    payload = client.get("/api/props").json()
    assert [row["id"] for row in payload["props"]] == ["fresh"]

    audit = client.get("/api/props", params={"includeStale": True}).json()
    assert {row["id"] for row in audit["props"]} == {"stale", "fresh"}


def test_recent_saved_catalog_remains_visible_while_recovery_runs(monkeypatch) -> None:
    from datetime import datetime, timedelta, timezone

    recovering = FakeProp("recovering", "One", "MLB", "FANDUEL", "HITS")
    recovering.lastUpdatedUtc = (
        datetime.now(timezone.utc) - timedelta(minutes=200)
    ).isoformat()
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [recovering])
    monkeypatch.setattr(
        main,
        "_sync_state_snapshot",
        lambda: {"status": "running"},
    )

    payload = TestClient(main.app).get("/api/props").json()

    assert [row["id"] for row in payload["props"]] == ["recovering"]
    assert payload["props"][0]["dataStale"] is True
    assert payload["staleFallback"]["active"] is True
    assert payload["staleFallback"]["reason"] == "recovery_running"


def test_recent_saved_catalog_stays_hidden_without_active_recovery(monkeypatch) -> None:
    from datetime import datetime, timedelta, timezone

    stale = FakeProp("stale-idle", "One", "MLB", "FANDUEL", "HITS")
    stale.lastUpdatedUtc = (
        datetime.now(timezone.utc) - timedelta(minutes=200)
    ).isoformat()
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [stale])
    monkeypatch.setattr(main, "_sync_state_snapshot", lambda: {"status": "idle"})

    payload = TestClient(main.app).get("/api/props").json()

    assert payload["props"] == []
    assert payload["staleFallback"]["active"] is False


def test_prop_feed_reports_recommendation_coverage(monkeypatch) -> None:
    model = FakeProp("model", "One", "MLB", "FANDUEL", "HITS")
    model.recommendationAvailable = True
    model.noVigOverProbability = 0.55
    model.noVigUnderProbability = 0.45
    market = FakeProp("market", "Two", "MLB", "FANDUEL", "HITS")
    market.recommendationAvailable = False
    market.noVigOverProbability = 0.54
    market.noVigUnderProbability = 0.46
    pending = FakeProp("pending", "Three", "MLB", "FANDUEL", "HITS")
    pending.recommendationAvailable = False
    pending.noVigOverProbability = 0.5
    pending.noVigUnderProbability = 0.5
    monkeypatch.setattr(
        main,
        "_cached_prop_catalog",
        lambda: [model, market, pending],
    )

    coverage = TestClient(main.app).get("/api/props").json()[
        "recommendationCoverage"
    ]
    assert coverage == {
        "modelPicks": 1,
        "baselinePicks": 0,
        "baselineProjections": 0,
        "suppressedWeakBaselineSignals": 0,
        "providerPicks": 1,
        "marketPicks": 1,
        "systemPicks": 2,
        "pending": 1,
        "total": 3,
    }


def test_prop_page_honors_etag(monkeypatch) -> None:
    monkeypatch.setattr(
        main,
        "_cached_prop_catalog",
        lambda: [FakeProp("pp-mlb", "One", "MLB", "PRIZEPICKS", "HITS")],
    )
    client = TestClient(main.app)
    first = client.get("/api/props", params={"sportsbook": "PRIZEPICKS", "limit": 1})
    second = client.get(
        "/api/props",
        params={"sportsbook": "PRIZEPICKS", "limit": 1},
        headers={"If-None-Match": first.headers["etag"]},
    )
    assert second.status_code == 304


def test_prop_page_reuses_verified_user_response_cache(monkeypatch) -> None:
    row = FakeProp("cached-prop", "One", "MLB", "PRIZEPICKS", "HITS")
    reliability_calls = []
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [row])
    monkeypatch.setattr(
        main,
        "build_provider_reliability",
        lambda *_args, **_kwargs: reliability_calls.append(True) or {},
    )
    before_hits = int(main._prop_metrics.get("cacheHits") or 0)
    client = TestClient(main.app)

    first = client.get("/api/props")
    second = client.get("/api/props")

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json() == first.json()
    assert reliability_calls == [True]
    assert int(main._prop_metrics["cacheHits"]) == before_hits + 1


def test_prop_response_cache_is_isolated_by_verified_user(monkeypatch) -> None:
    row = FakeProp("isolated-prop", "One", "MLB", "PRIZEPICKS", "HITS")
    reliability_calls = []
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [row])
    monkeypatch.setattr(
        main,
        "build_provider_reliability",
        lambda *_args, **_kwargs: reliability_calls.append(True) or {},
    )
    client = TestClient(main.app)
    main.app.dependency_overrides[main.require_core] = lambda: main.Membership(
        "cache-user-one",
        main.AccessLevel.PRO,
        "pro",
        "user",
    )
    try:
        first = client.get("/api/props")
        main.app.dependency_overrides[main.require_core] = lambda: main.Membership(
            "cache-user-two",
            main.AccessLevel.PRO,
            "pro",
            "user",
        )
        second = client.get("/api/props")
    finally:
        main.app.dependency_overrides.pop(main.require_core, None)

    assert first.status_code == 200
    assert second.status_code == 200
    assert reliability_calls == [True, True]


def test_prop_response_cache_changes_with_catalog_timestamp(monkeypatch) -> None:
    row = FakeProp("versioned-prop", "One", "MLB", "PRIZEPICKS", "HITS")
    reliability_calls = []
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [row])
    monkeypatch.setattr(
        main,
        "build_provider_reliability",
        lambda *_args, **_kwargs: reliability_calls.append(True) or {},
    )
    client = TestClient(main.app)

    assert client.get("/api/props").status_code == 200
    row.lastUpdatedUtc = "2099-07-20T19:56:00Z"
    assert client.get("/api/props").status_code == 200

    assert reliability_calls == [True, True]


def test_prop_filtering_serializes_only_the_requested_page(monkeypatch) -> None:
    rows = [
        FakeProp(f"prop-{index}", f"Player {index}", "MLB", "FANDUEL", "HITS")
        for index in range(100)
    ]
    dumps = 0
    original_dump = FakeProp.model_dump

    def counted_dump(prop: FakeProp) -> dict[str, object]:
        nonlocal dumps
        dumps += 1
        return original_dump(prop)

    monkeypatch.setattr(FakeProp, "model_dump", counted_dump)
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: rows)

    response = TestClient(main.app).get("/api/props?limit=1")

    assert response.status_code == 200
    assert response.json()["returned"] == 1
    assert dumps == 1


def test_catalog_reuses_models_when_distributed_version_is_unchanged(
    monkeypatch,
) -> None:
    rows = [FakeProp("prop-1", "Player", "MLB", "FANDUEL", "HITS")]
    main._prop_catalog.update(
        loadedAt=main.time.monotonic(),
        versionCheckedAt=0.0,
        version="catalog-v1",
        props=rows,
    )
    reads: list[str] = []

    def fake_get(key: str):
        reads.append(key)
        return "catalog-v1"

    monkeypatch.setattr(main, "get_distributed_json", fake_get)

    try:
        assert main._cached_prop_catalog() is rows
        assert reads == ["props:catalog:version:v1"]
    finally:
        main._prop_catalog.update(
            loadedAt=0.0,
            versionCheckedAt=0.0,
            version=None,
            props=[],
        )


def test_cached_catalog_verdicts_are_recomputed_for_the_running_release(
    monkeypatch,
) -> None:
    prop = FakeProp("prop-1", "Player", "MLB", "FANDUEL", "HITS")
    prop.verdict = {"decision": "PASS"}
    verdict = object()
    monkeypatch.setattr(main, "compute_verdict", lambda row: verdict)
    monkeypatch.setattr(
        main,
        "verdict_payload",
        lambda value: {"decision": "LEAN", "actionable": True},
    )

    result = main._recompute_runtime_verdicts([prop])

    assert result == [prop]
    assert prop.verdict == {"decision": "LEAN", "actionable": True}


def test_cached_catalog_upgrades_local_player_photo_to_official_headshot(
    monkeypatch,
) -> None:
    prop = FakeProp("wnba-photo", "Breanna Stewart", "WNBA", "FANDUEL", "POINTS")
    prop.imagePath = "/player-images/breanna_stewart.png"
    official = "https://a.espncdn.com/i/headshots/wnba/players/full/2998928.png"
    monkeypatch.setattr(main, "resolve_player_image", lambda *_args: official)

    main._recompute_runtime_verdicts([prop])

    assert prop.imagePath == official


def test_cached_catalog_preserves_valid_remote_player_photo(monkeypatch) -> None:
    prop = FakeProp("remote-photo", "Player", "WNBA", "FANDUEL", "POINTS")
    prop.imagePath = "https://images.example.com/current.png"
    calls = []
    monkeypatch.setattr(
        main,
        "resolve_player_image",
        lambda *_args: calls.append(True) or "https://replacement.invalid/image.png",
    )

    main._recompute_runtime_verdicts([prop])

    assert prop.imagePath == "https://images.example.com/current.png"
    assert calls == []


def test_positive_ev_route_returns_only_calculated_positive_rows(monkeypatch) -> None:
    positive = FakeProp("positive", "One", "MLB", "FANDUEL", "HITS")
    positive.evPercentage = 4.25
    positive.fairProbability = 0.57
    positive.isPositiveEv = True
    unavailable = FakeProp("missing", "Two", "MLB", "FANDUEL", "HITS")
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [positive, unavailable])

    response = TestClient(main.app).get(
        "/api/props/ev",
        params={"min_ev": 2, "sport": "MLB"},
    )

    assert response.status_code == 200
    assert response.json()["count"] == 1
    assert response.json()["props"][0]["id"] == "positive"


def test_game_market_route_exposes_moneylines_spreads_and_totals(monkeypatch) -> None:
    monkeypatch.setattr(
        main,
        "get_game_markets",
        lambda sport, force=False: {
            "sport": sport,
            "cached": False,
            "updatedAt": "2026-07-19T20:00:00Z",
            "events": [{
                "id": "game-1",
                "bookmakers": [{
                    "markets": {"h2h": [], "spreads": [], "totals": []}
                }],
            }],
        },
    )
    response = TestClient(main.app).get("/api/game-markets?sport=MLB")
    assert response.status_code == 200
    assert response.json()["sport"] == "MLB"
    markets = response.json()["events"][0]["bookmakers"][0]["markets"]
    assert set(markets) == {"h2h", "spreads", "totals"}


def test_prop_feed_monitor_reports_payload_and_freshness(monkeypatch) -> None:
    from datetime import datetime, timezone

    prop = FakeProp("fresh", "One", "MLB", "FANDUEL", "HITS")
    prop.lastUpdatedUtc = datetime.now(timezone.utc).isoformat()
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [prop])
    client = TestClient(main.app)
    assert client.get("/api/props").status_code == 200
    health = client.get("/api/operations/prop-feed-health").json()
    assert health["status"] == "ok"
    assert health["latestEmpty"] is False
    assert health["stale"] is False
    assert health["lastTotalCount"] == 1
    assert health["lastPayloadBytes"] > 0


def test_prop_feed_monitor_uses_shared_catalog_after_restart(monkeypatch) -> None:
    """A new API instance must not call a healthy shared feed empty."""

    from datetime import datetime, timezone

    updated_at = datetime.now(timezone.utc).isoformat()
    monkeypatch.setattr(
        main,
        "get_distributed_json",
        lambda key: {
            "count": 4738,
            "lastDataUpdatedAt": updated_at,
            "version": "deployed",
        } if key == main._PROP_CATALOG_SUMMARY_KEY else None,
    )
    monkeypatch.setattr(main, "_prop_metrics", {
        "requests": 0,
        "errors": 0,
        "emptyResponses": 0,
        "lastDurationMs": 0,
        "lastPayloadBytes": 0,
        "lastServedAt": None,
        "lastTotalCount": 0,
        "lastDataUpdatedAt": None,
        "lastRequestSucceeded": None,
    })

    health = TestClient(main.app).get("/api/operations/prop-feed-health").json()

    assert health["status"] == "ok"
    assert health["latestEmpty"] is False
    assert health["stale"] is False
    assert health["lastTotalCount"] == 4738


def test_prop_feed_monitor_falls_back_to_catalog_when_summary_is_missing(
    monkeypatch,
) -> None:
    """Redis summary loss must not make an available protected feed look empty."""

    from datetime import datetime, timezone

    prop = FakeProp("fallback", "One", "MLB", "FANDUEL", "HITS")
    prop.lastUpdatedUtc = datetime.now(timezone.utc).isoformat()
    monkeypatch.setattr(main, "get_distributed_json", lambda _key: None)
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [prop])
    monkeypatch.setattr(main, "_prop_metrics", {
        "requests": 0,
        "errors": 0,
        "emptyResponses": 0,
        "lastDurationMs": 0,
        "lastPayloadBytes": 0,
        "lastServedAt": None,
        "lastTotalCount": 0,
        "lastDataUpdatedAt": None,
        "lastRequestSucceeded": None,
    })

    response = TestClient(main.app).get("/api/operations/prop-feed-health")
    health = response.json()

    assert response.headers["cache-control"] == "private, no-store, max-age=0"
    assert health["status"] == "ok"
    assert health["latestEmpty"] is False
    assert health["lastTotalCount"] == 1


def test_edge_ranking_uses_no_vig_probability_not_stat_units(monkeypatch) -> None:
    # A three-yard edge on a wide market is worth less than a small edge on a
    # tight one, and the posted price decides which is actually a bet. Ranking
    # on raw stat units gets both wrong.
    wide = FakeProp("yards", "Receiver", "NFL", "FANDUEL", "RECEIVING_YARDS")
    wide.edge = 3.0
    wide.probabilityEdge = .01
    wide.evPercentage = .4
    tight = FakeProp("strikeouts", "Pitcher", "MLB", "FANDUEL", "STRIKEOUTS")
    tight.edge = 0.8
    tight.probabilityEdge = .07
    tight.evPercentage = 5.2
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [wide, tight])

    response = TestClient(main.app).get(
        "/api/props",
        params={"sport": "All", "sortBy": "edge"},
    )

    assert response.status_code == 200
    assert [row["id"] for row in response.json()["props"]] == [
        "strikeouts",
        "yards",
    ]

def test_edge_ranking_keeps_earlier_games_before_later_games(monkeypatch) -> None:
    earlier = FakeProp("earlier", "Early", "MLB", "FANDUEL", "STRIKEOUTS")
    earlier.startTimeUtc = "2099-07-20T20:00:00Z"
    earlier.probabilityEdge = .01
    later = FakeProp("later", "Late", "MLB", "FANDUEL", "STRIKEOUTS")
    later.startTimeUtc = "2099-07-21T20:00:00Z"
    later.probabilityEdge = .20
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [later, earlier])

    response = TestClient(main.app).get(
        "/api/props",
        params={"sport": "All", "sortBy": "edge"},
    )

    assert response.status_code == 200
    assert [row["id"] for row in response.json()["props"]] == [
        "earlier",
        "later",
    ]


def test_edge_ranking_puts_unpriced_props_last(monkeypatch) -> None:
    priced = FakeProp("priced", "One", "NBA", "FANDUEL", "POINTS")
    priced.edge = 0.5
    priced.probabilityEdge = -.02
    unpriced = FakeProp("unpriced", "Two", "NBA", "FANDUEL", "POINTS")
    unpriced.edge = 9.0
    unpriced.probabilityEdge = None
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [unpriced, priced])

    response = TestClient(main.app).get(
        "/api/props",
        params={"sport": "All", "sortBy": "edge"},
    )

    assert response.status_code == 200
    assert [row["id"] for row in response.json()["props"]] == [
        "priced",
        "unpriced",
    ]


def test_confidence_scales_by_the_market_not_by_stat_units() -> None:
    """A yard and a strikeout are not the same distance.

    The previous formula added twelve points of confidence per stat unit, so
    three yards of receiving yards scored the same as three points of
    basketball, and a large strikeout edge scored far less than either.
    """

    from services.prop_recommendation_service import build_prop_recommendation

    yards = build_prop_recommendation(
        103.0, 100.0, sport="NFL", market="player_reception_yds", volatility=32,
    )
    strikeouts = build_prop_recommendation(
        6.3, 5.5, sport="MLB", market="pitcher_strikeouts",
    )

    # Three yards is noise on a market that swings thirty; eight tenths of a
    # strikeout is not, on a market that swings one and a half.
    assert yards["confidence"] < strikeouts["confidence"]
    assert yards["confidence"] < 60


def test_confidence_still_rises_with_the_edge_within_one_market() -> None:
    from services.prop_recommendation_service import build_prop_recommendation

    small = build_prop_recommendation(19.0, 18.5, sport="NBA", market="player_points")
    large = build_prop_recommendation(23.0, 18.5, sport="NBA", market="player_points")

    assert large["confidence"] > small["confidence"]
    assert 50 <= small["confidence"] <= 99


def test_edge_stays_in_stat_units_for_display() -> None:
    from services.prop_recommendation_service import build_prop_recommendation

    # The card shows "+1.9"; only confidence is rescaled.
    result = build_prop_recommendation(
        25.4, 23.5, sport="NBA", market="player_points",
    )
    assert result["edge"] == pytest.approx(1.9, abs=1e-6)


def test_only_a_market_impossible_for_its_sport_is_withheld_from_the_board() -> None:
    """A market its sport does not have is the one thing that cannot be shown.

    Everything else -- an unnamed source, a missing projection -- is a hole
    in our metadata about a real prop, not evidence the prop is fake, so it
    stays on the board explained rather than hidden. Repeating "Player
    Points" on a baseball card verbatim was the actual defect; "UNKNOWN" as a
    source is now a caveat, not a disappearance.
    """

    from models.prop import PropResponse
    from services.prop_service import _verified_props

    def prop(**over):
        base = dict(
            id="a", player="Drew Romo", sport="MLB",
            matchup="Cleveland Guardians @ Chicago White Sox",
            sportsbook="PRIZEPICKS", market="Batter Hits",
            marketKey="batter_hits", line=0.5, projection=0.62,
            pick="Over", edge=0.12,
        )
        base.update(over)
        return PropResponse(**base)

    shown = _verified_props([
        prop(),
        prop(id="b", marketKey="player_points", market="Player Points"),
        prop(id="c", sportsbook="UNKNOWN"),
        prop(id="d", projection=None),
    ])
    by_id = {p.id: p for p in shown}

    # Only the impossible market is gone.
    assert set(by_id) == {"a", "c", "d"}

    assert by_id["a"].verificationStatus == "verified"
    assert by_id["a"].selectable is True

    # An unnamed source stays selectable and says why.
    assert by_id["c"].selectable is True
    assert "source_unverified" in by_id["c"].verificationReasons

    # A missing projection is a gap in our coverage, not a defect in the prop,
    # so it stays selectable and simply says so.
    assert by_id["d"].selectable is True
    assert "projection_missing" in by_id["d"].verificationReasons


def test_team_identifiers_never_reach_a_card() -> None:
    from services.prop_verification_service import display_matchup

    # 47% of live matchups carried underscores before this.
    assert display_matchup(
        "CLEVELAND_GUARDIANS_MLB @ CHICAGO_WHITE_SOX_MLB"
    ) == "Cleveland Guardians @ Chicago White Sox"


def test_catalog_cold_load_is_single_flight(monkeypatch) -> None:
    active = 0
    max_active = 0
    guard = Lock()
    result = [object()]

    def fake_load():
        nonlocal active, max_active
        with guard:
            active += 1
            max_active = max(max_active, active)
        time.sleep(0.02)
        with guard:
            active -= 1
        return result

    monkeypatch.setattr(main, "_cached_prop_catalog_singleflight", fake_load)

    with ThreadPoolExecutor(max_workers=8) as executor:
        responses = list(executor.map(lambda _: main._cached_prop_catalog(), range(8)))

    assert responses == [result] * 8
    assert max_active == 1


def test_save_slip_reuses_cached_catalog_instead_of_rebuilding_feed(
    monkeypatch,
) -> None:
    class CurrentProp:
        id = "prop-1"
        gameStatus = "scheduled"
        startTimeUtc = "2099-07-20T20:00:00Z"
        gameStartTime = ""

    class SavedSlip:
        id = "slip-1"

        @staticmethod
        def model_dump(mode=None):
            return {"id": "slip-1", "status": "active", "legs": []}

    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [CurrentProp()])
    monkeypatch.setattr(
        main,
        "get_props",
        lambda: pytest.fail("ticket lock rebuilt the full raw prop catalog"),
    )
    monkeypatch.setattr(
        main,
        "create_slip",
        lambda request, user_id: SavedSlip(),
    )
    monkeypatch.setattr(
        main.realtime_hub,
        "broadcast_user_from_thread",
        lambda *args, **kwargs: None,
    )

    request = main.SlipCreate(
        legs=[
            {
                "prop_id": "prop-1",
                "player": "Example Player",
                "sport": "MLB",
                "matchup": "Away @ Home",
                "sportsbook": "PrizePicks",
                "market": "Hits",
                "line": 1.5,
                "side": "OVER",
            },
        ],
        stake=10,
        client_request_id="ticket-cache-test",
    )

    response = main.save_slip(request, user_id="test-user")

    assert response["status"] == "saved"
    assert request.legs[0].game_start_time == "2099-07-20T20:00:00Z"
