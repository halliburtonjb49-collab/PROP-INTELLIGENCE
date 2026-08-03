from datetime import datetime, timezone

import pytest

from services.historical_odds_service import (
    clv_checkpoint_times, historical_credit_cost, unwrap_historical_snapshot,
)
from services.market_intelligence_service import normalized_book_rows


def test_historical_credit_cost_is_ten_per_region_market() -> None:
    assert historical_credit_cost(["player_points", "player_points", "player_assists"], ["us", "eu"]) == 40


def test_clv_checkpoints_are_ordered_and_stop_before_tip() -> None:
    tip = datetime(2026, 8, 2, 18, tzinfo=timezone.utc)
    checkpoints = clv_checkpoint_times(tip)
    assert len(checkpoints) == 4
    assert checkpoints == sorted(checkpoints)
    assert checkpoints[-1] < tip


def test_historical_wrapper_and_player_prop_pair_normalize() -> None:
    payload = {"timestamp": "2026-08-02T17:55:00Z", "data": {
        "id": "event-1", "bookmakers": [{"key": "draftkings", "markets": [{
            "key": "player_points", "outcomes": [
                {"name": "Over", "description": "A Player", "point": 21.5, "price": -110},
                {"name": "Under", "description": "A Player", "point": 21.5, "price": -120},
            ]}]}]}}
    timestamp, event = unwrap_historical_snapshot(payload)
    rows = normalized_book_rows(provider="history", sport="basketball_wnba", event_id="event-1", payload=event)
    assert timestamp == datetime(2026, 8, 2, 17, 55, tzinfo=timezone.utc)
    assert rows == [{"provider": "history", "sport": "basketball_wnba", "event_id": "event-1",
                     "player": "A Player", "market": "player_points", "bookmaker": "draftkings",
                     "line": 21.5, "over_odds": -110.0, "under_odds": -120.0}]


def test_invalid_historical_timestamp_is_tolerated() -> None:
    timestamp, event = unwrap_historical_snapshot({"timestamp": "bad", "data": {}})
    assert timestamp is None
    assert event == {}
