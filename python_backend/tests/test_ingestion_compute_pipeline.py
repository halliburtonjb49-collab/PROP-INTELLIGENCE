from __future__ import annotations

import msgspec
from fastapi.testclient import TestClient

import main

from services.market_intelligence_service import (
    compute_market_intelligence,
    normalized_book_rows,
)
from services.raw_ingestion_service import RawFeedEnvelope
from services import raw_ingestion_service
from providers.sportsgameodds import _market_key


def _payload() -> dict[str, object]:
    return {
        "bookmakers": [
            {
                "title": "Book A",
                "markets": [{
                    "key": "player_points",
                    "outcomes": [
                        {"name": "Over", "description": "A Player", "point": 20.5, "price": -110},
                        {"name": "Under", "description": "A Player", "point": 20.5, "price": -105},
                    ],
                }],
            },
            {
                "title": "Book B",
                "markets": [{
                    "key": "player_points",
                    "outcomes": [
                        {"name": "Over", "description": "A Player", "point": 21.5, "price": 105},
                        {"name": "Under", "description": "A Player", "point": 21.5, "price": -115},
                    ],
                }],
            },
        ],
    }


def test_raw_feed_envelope_is_validated_by_msgspec() -> None:
    envelope = RawFeedEnvelope(
        provider="odds-api",
        sport="basketball_nba",
        event={"id": "game-1"},
        payload=_payload(),
        fetched_at="2026-07-28T12:00:00+00:00",
    )
    encoded = msgspec.json.encode(envelope)
    decoded = msgspec.json.decode(encoded, type=RawFeedEnvelope)

    assert decoded.provider == "odds-api"
    assert decoded.event["id"] == "game-1"


def test_polars_computes_consensus_and_best_prices_across_books() -> None:
    rows = normalized_book_rows(
        provider="odds-api",
        sport="basketball_nba",
        event_id="game-1",
        payload=_payload(),
    )
    intelligence = compute_market_intelligence(rows)

    assert len(rows) == 2
    assert intelligence == [{
        "sport": "basketball_nba",
        "event_id": "game-1",
        "player": "A Player",
        "market": "player_points",
        "consensus_line": 21.0,
        "book_count": 2,
        "best_over_odds": 105.0,
        "best_over_book": "Book B",
        "best_under_odds": -105.0,
        "best_under_book": "Book A",
    }]


def test_pipeline_queues_fetch_jobs_before_any_normalization(monkeypatch) -> None:
    calls: list[tuple[str, tuple[object, ...]]] = []

    def fake_enqueue(function_name: str, **kwargs):
        calls.append((function_name, kwargs.get("args", ())))
        return {"id": kwargs.get("job_id")}

    monkeypatch.setattr(raw_ingestion_service, "enqueue", fake_enqueue)
    result = raw_ingestion_service.queue_ingestion_pipeline([
        "baseball_mlb",
        "basketball_nba",
    ])

    assert result["mode"] == "redis-stream"
    assert result["queuedSports"] == ["baseball_mlb", "basketball_nba"]
    assert calls == [
        ("jobs.fetch_sport_raw", ("baseball_mlb",)),
        ("jobs.fetch_sport_raw", ("basketball_nba",)),
        ("jobs.fetch_sportsgameodds_raw", ()),
    ]


def test_market_intelligence_endpoint_exposes_computed_rows(monkeypatch) -> None:
    monkeypatch.setattr(
        main,
        "latest_market_intelligence",
        lambda **_kwargs: [{"sport": "basketball_nba", "consensus_line": 21.0}],
    )

    response = TestClient(main.app).get(
        "/api/market-intelligence?sport=basketball_nba&limit=10"
    )

    assert response.status_code == 200
    assert response.json()["count"] == 1


def test_tennis_uses_documented_sportsgameodds_stat_ids() -> None:
    assert _market_key(
        stat_id="serving_aces",
        sport_key="tennis_atp",
        bet_type="ou",
        market_name="Serving Aces",
    ) == "player_aces"
    assert _market_key(
        stat_id="breakPoints",
        sport_key="tennis_wta",
        bet_type="ou",
        market_name="Break Points Won",
    ) == "player_break_points_won"


def test_golf_and_ufc_stat_ids_map_to_player_props() -> None:
    assert _market_key(
        stat_id="birdies", sport_key="golf_pga", bet_type="ou",
        market_name="Rory McIlroy Birdies",
    ) == "player_birdies"
    assert _market_key(
        stat_id="significantStrikes", sport_key="mma_mixed_martial_arts",
        bet_type="ou", market_name="Fighter Significant Strikes",
    ) == "fighter_significant_strikes"


def test_ingestion_reuses_one_redis_connection_pool(monkeypatch) -> None:
    clients: list[object] = []
    sentinel = object()
    monkeypatch.setattr(raw_ingestion_service, "REDIS_URL", "redis://example")
    monkeypatch.setattr(
        raw_ingestion_service.Redis,
        "from_url",
        lambda *_args, **_kwargs: clients.append(sentinel) or sentinel,
    )
    raw_ingestion_service._redis.cache_clear()
    try:
        assert raw_ingestion_service._redis() is sentinel
        assert raw_ingestion_service._redis() is sentinel
        assert len(clients) == 1
    finally:
        raw_ingestion_service._redis.cache_clear()
