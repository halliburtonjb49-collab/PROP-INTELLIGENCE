from dataclasses import dataclass

from fastapi.testclient import TestClient

import main


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
    lastUpdatedUtc: str = "2026-07-18T20:00:00Z"

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
    assert "stale-while-revalidate" in response.headers["cache-control"]


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
