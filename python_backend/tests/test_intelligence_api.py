from fastapi.testclient import TestClient

from main import app


client = TestClient(app)


def _leg(identifier: str, player: str, market: str) -> dict[str, str]:
    return {
        "id": identifier,
        "player": player,
        "team": "",
        "opponent": "",
        "game_id": "game-1",
        "sport": "NFL",
        "market": market,
        "side": "OVER",
    }


def test_capabilities_are_discoverable() -> None:
    response = client.get("/api/intelligence/capabilities")
    assert response.status_code == 200
    assert "correlations" in response.json()["features"]


def test_integrated_lab_workflow() -> None:
    legs = [
        _leg("qb", "Quarterback", "Passing Yards"),
        _leg("wr", "Receiver", "Receiving Yards"),
    ]

    correlation = client.post("/api/intelligence/correlations", json={"legs": legs})
    simulation = client.post(
        "/api/intelligence/game-script",
        json={
            "script": "SHOOTOUT",
            "sport": "NFL",
            "simulations": 1000,
            "props": [
                {**legs[0], "baseline_projection": 280, "line": 265.5},
                {**legs[1], "baseline_projection": 85, "line": 74.5},
            ],
        },
    )
    sentiment = client.post(
        "/api/intelligence/sentiment",
        json=[{"prop_id": "qb", "action": "PICK_OVER"}],
    )
    alert = client.post(
        "/api/intelligence/alerts/evaluate",
        json={
            "name": "Correlated public play",
            "logic": "ALL",
            "snapshot": {"correlation": 0.62, "interest": 10},
            "conditions": [
                {"field": "correlation", "operator": "GTE", "value": 0.35},
                {"field": "interest", "operator": "GTE", "value": 8},
            ],
        },
    )

    assert correlation.status_code == 200
    assert correlation.json()["pairs"][0]["classification"] == "POSITIVE"
    assert simulation.status_code == 200
    assert len(simulation.json()["impacts"]) == 2
    assert simulation.json()["simulations"] == 1000
    assert simulation.json()["portfolioHitProbability"] is not None
    assert sentiment.status_code == 200
    assert sentiment.json()["score"] == 5
    assert alert.status_code == 200
    assert alert.json()["triggered"] is True


def test_invalid_correlation_payload_is_rejected() -> None:
    response = client.post(
        "/api/intelligence/correlations",
        json={"legs": [_leg("only", "Player", "Points")]},
    )
    assert response.status_code == 422


def test_historical_features_endpoint() -> None:
    response = client.post("/api/intelligence/historical-features", json={
        "values": [10, 12, 14, 16, 18], "minutes": [28, 30, 31, 32, 34], "window": 5,
    })
    assert response.status_code == 200
    assert response.json()["recommendedProjection"] > 0


def test_calibration_endpoint_degrades_cleanly_without_database() -> None:
    response = client.get("/api/intelligence/calibration")
    assert response.status_code == 200
    assert "sampleSize" in response.json()


def test_closing_line_value_endpoint() -> None:
    response = client.post("/api/intelligence/closing-line-value", json={
        "side": "OVER", "entry_line": 20.5, "closing_line": 22.5,
        "entry_odds": 100, "closing_odds": -110,
    })
    assert response.status_code == 200
    assert response.json()["beatClosingLine"] is True
