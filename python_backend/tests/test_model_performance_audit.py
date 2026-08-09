from services.model_performance_service import (
    _audit_recommendation,
    _dominant_model_version,
    _is_quarantined_market,
    _ledger_metadata,
    _rolling_row,
    _summarize_roi_clv_segments,
)


class _FakeCursor:
    def __init__(self, row):
        self._row = row

    def execute(self, _query):
        pass

    def fetchone(self):
        return self._row


def test_dominant_model_version_returns_the_top_row() -> None:
    cursor = _FakeCursor(("provider-projection-v1", 85))
    assert _dominant_model_version(cursor) == "provider-projection-v1"


def test_dominant_model_version_handles_no_graded_rows() -> None:
    cursor = _FakeCursor(None)
    assert _dominant_model_version(cursor) is None


def test_dominant_model_version_handles_null_version() -> None:
    cursor = _FakeCursor((None, 3))
    assert _dominant_model_version(cursor) is None


def test_audit_waits_for_a_safe_sample() -> None:
    result = _audit_recommendation(12, 0.75, 0.80)
    assert result["status"] == "COLLECTING"
    assert result["actionable"] is False


def test_audit_flags_underperforming_segment() -> None:
    result = _audit_recommendation(50, 0.46, 0.62)
    assert result["status"] == "RECALIBRATE"
    assert result["actionable"] is True


def test_audit_accepts_calibrated_segment() -> None:
    result = _audit_recommendation(50, 0.61, 0.63)
    assert result["status"] == "HEALTHY"
    assert result["calibrationGap"] == 0.02


def test_rolling_row_reports_accuracy_confidence_and_status() -> None:
    result = _rolling_row("sport", ("WNBA", 100, 42, 0.61))
    assert result["value"] == "WNBA"
    assert result["accuracy"] == 0.42
    assert result["averageConfidence"] == 0.61
    assert result["calibrationGap"] == 0.19
    assert result["status"] == "RECALIBRATE"


def test_quarantines_wnba_and_nba_fantasy_markets_from_reporting() -> None:
    assert _is_quarantined_market("WNBA", "player_fantasy_points") is True
    assert _is_quarantined_market("WNBA", "Fantasy Points") is True
    assert _is_quarantined_market("NBA", "player_fantasy_points") is True
    assert _is_quarantined_market("NBA", "player_points") is False
    assert _is_quarantined_market("MLB", "batter_hits") is False


def test_summarizes_roi_and_clv_by_side_and_market() -> None:
    rows = [
        {
            "sport": "NBA",
            "market": "player_points",
            "side": "OVER",
            "sampleSize": 10,
            "hits": 6,
            "averageConfidence": 0.61,
            "simulatedRoi": 0.12,
            "beatClosingLineRate": 0.6,
            "averageLineClvPoints": 1.5,
            "averageOddsClvExpectedValuePercent": 4.2,
            "positiveOddsClvRate": 0.7,
            "oddsSampleSize": 8,
        },
        {
            "sport": "NBA",
            "market": "player_points",
            "side": "UNDER",
            "sampleSize": 10,
            "hits": 4,
            "averageConfidence": 0.39,
            "simulatedRoi": -0.08,
            "beatClosingLineRate": 0.4,
            "averageLineClvPoints": -0.8,
            "averageOddsClvExpectedValuePercent": -1.3,
            "positiveOddsClvRate": 0.3,
            "oddsSampleSize": 8,
        },
    ]

    result = _summarize_roi_clv_segments(rows)

    assert len(result) == 2
    assert result[0]["sport"] == "NBA"
    assert result[0]["market"] == "player_points"
    assert result[0]["side"] == "OVER"
    assert result[0]["accuracy"] == 0.6
    assert result[0]["simulatedRoi"] == 0.12
    assert result[0]["beatClosingLineRate"] == 0.6
    assert result[1]["side"] == "UNDER"
    assert result[1]["positiveOddsClvRate"] == 0.3


def test_ledger_metadata_reports_latest_streak_without_hiding_losses() -> None:
    result = _ledger_metadata([
        (False, "2026-08-08T12:00:00+00:00"),
        (False, "2026-08-08T11:00:00+00:00"),
        (True, "2026-08-08T10:00:00+00:00"),
    ])
    assert result["currentStreak"] == {"type": "LOSING", "length": 2}
    assert result["lastGradedAt"] == "2026-08-08T12:00:00+00:00"