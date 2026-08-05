from types import SimpleNamespace
from datetime import datetime

from services import strikeout_quality_service


def test_release_gate_blocks_stale_lineup_and_missing_signals() -> None:
    prop = SimpleNamespace(
        mlbProjectedLineupMatchup={
            "confirmed": True,
            "observedAt": "2026-08-01T00:00:00Z",
            "opposingLineup": [{"player": "A"}] * 9,
        },
        temperatureF=70.0,
        umpireKBoost=0.01,
        lineupKPercent=0.22,
        lineupCswAgainst=None,
        strikeoutUsedFallbackPitcherRate=False,
        strikeoutUsedFallbackLineupRate=False,
        strikeoutUsedFallbackTbf=False,
    )
    controls = {
        "enabled": True,
        "maxLineupAgeMinutes": 60,
        "minOpposingLineupSize": 8,
        "requireConfirmedLineup": True,
        "requireTemperature": True,
        "requireUmpireBoost": True,
        "requireSplitSignal": True,
        "maxFallbackSignals": 0,
    }

    result = strikeout_quality_service.evaluate_release_gate(prop, controls)

    assert result.blocked is True
    assert result.reason == "strikeout_lineup_stale"


def test_release_gate_blocks_when_fallback_count_exceeds_limit() -> None:
    prop = SimpleNamespace(
        mlbProjectedLineupMatchup={
            "confirmed": True,
            "observedAt": "2026-08-05T12:00:00Z",
            "opposingLineup": [{"player": "A"}] * 9,
        },
        temperatureF=70.0,
        umpireKBoost=0.01,
        lineupKPercent=0.22,
        lineupCswAgainst=None,
        strikeoutUsedFallbackPitcherRate=True,
        strikeoutUsedFallbackLineupRate=False,
        strikeoutUsedFallbackTbf=False,
    )

    result = strikeout_quality_service.evaluate_release_gate(
        prop,
        {
            "enabled": True,
            "maxLineupAgeMinutes": 480,
            "minOpposingLineupSize": 8,
            "requireConfirmedLineup": True,
            "requireTemperature": True,
            "requireUmpireBoost": True,
            "requireSplitSignal": True,
            "maxFallbackSignals": 0,
        },
    )

    assert result.blocked is True
    assert result.reason == "strikeout_fallback_over_limit"


def test_build_explainability_snippet_compacts_key_factors() -> None:
    prop = SimpleNamespace(
        strikeoutModelMethod="mlb_strikeout_log5_binomial",
        recommendedSide="Over",
        line=5.5,
        fairProbability=0.62,
        pitcherKPercent=0.31,
        lineupKPercent=0.24,
        strikeoutProjectedBattersFaced=24,
        temperatureF=64.0,
        umpireKBoost=0.01,
        parkKFactor=1.02,
        strikeoutUsedFallbackPitcherRate=False,
        strikeoutUsedFallbackLineupRate=False,
        strikeoutUsedFallbackTbf=True,
    )

    summary = strikeout_quality_service.build_explainability_snippet(prop)

    assert "mlb_strikeout_log5_binomial" in summary
    assert "line 5.5" in summary
    assert "fallbacks 1" in summary


def test_get_controls_falls_back_when_database_missing(monkeypatch) -> None:
    monkeypatch.setattr(strikeout_quality_service, "database_is_configured", lambda: False)

    result = strikeout_quality_service.get_strikeout_release_controls()

    assert result["configured"] is False
    assert result["source"] == "defaults"
    assert result["controls"]["enabled"] is True


def test_calibration_history_uses_fixed_windows_and_guardrails(monkeypatch) -> None:
    monkeypatch.setattr(strikeout_quality_service, "database_is_configured", lambda: True)

    def _fake_rows(window_days: int) -> list[tuple[object, ...]]:
        if window_days == 7:
            return [
                ("book_a", "5_TO_6_5", "MID_K", "R", "OVER", 50, 0.58, 0.62, 0.225),
            ]
        if window_days == 30:
            return [
                ("book_b", "GT_6_5", "HIGH_K", "L", "UNDER", 80, 0.56, 0.58, 0.219),
            ]
        return [
            ("book_c", "LT_5", "LOW_K", "R", "OVER", 120, 0.61, 0.62, 0.207),
        ]

    monkeypatch.setattr(strikeout_quality_service, "_slice_rows", _fake_rows)

    result = strikeout_quality_service.strikeout_calibration_history_report(
        {
            "driftMinSample": 40,
            "calibrationGapWarn": 0.03,
            "calibrationGapHard": 0.05,
        }
    )

    assert result["available"] is True
    assert result["fixedWindowsDays"] == [7, 30, 90]
    assert len(result["windows"]) == 3
    seven_day = result["windows"][0]
    assert seven_day["windowDays"] == 7
    assert seven_day["slices"][0]["sportsbook"] == "book_a"
    assert seven_day["slices"][0]["lineBand"] == "5_TO_6_5"
    assert seven_day["slices"][0]["handedness"] == "R"
    assert seven_day["slices"][0]["side"] == "OVER"
    assert seven_day["slices"][0]["brier"] == 0.225
    assert seven_day["slices"][0]["calibrationGap"] == 0.04
    assert seven_day["slices"][0]["hitRateDeltaVsPredicted"] == -0.04
    assert seven_day["slices"][0]["guardrailStatus"] == "warning"
    assert result["warnings"] >= 1
    assert result["hardBreaches"] == 0


def test_calibration_history_marks_hard_breach(monkeypatch) -> None:
    monkeypatch.setattr(strikeout_quality_service, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        strikeout_quality_service,
        "_slice_rows",
        lambda _window_days: [
            ("book_z", "GT_6_5", "HIGH_K", "L", "UNDER", 60, 0.52, 0.60, 0.24),
        ],
    )

    result = strikeout_quality_service.strikeout_calibration_history_report(
        {
            "driftMinSample": 40,
            "calibrationGapWarn": 0.03,
            "calibrationGapHard": 0.05,
        }
    )

    assert result["available"] is True
    assert result["hardBreaches"] >= 1
    assert result["healthy"] is False


def test_weekly_trust_report_includes_regimes_and_cross_book_status(monkeypatch) -> None:
    monkeypatch.setattr(strikeout_quality_service, "database_is_configured", lambda: True)
    monkeypatch.setattr(
        strikeout_quality_service,
        "_weekly_trend_rows",
        lambda _lookback_days=90: [
            (datetime(2026, 8, 3).date(), "book_a", "pitcher_strikeouts", 30, 0.6, 0.57, 0.22, 1.2, 0.05),
        ],
    )
    monkeypatch.setattr(
        strikeout_quality_service,
        "_regime_split_rows",
        lambda _lookback_days=90: [
            ("fallback", "fallback_heavy", 20, 0.58, 0.5, 0.24, 0.6),
            ("line", "high_line", 18, 0.59, 0.56, 0.23, 0.8),
            ("timing", "close_to_game", 25, 0.6, 0.58, 0.21, 1.0),
        ],
    )
    monkeypatch.setattr(
        strikeout_quality_service,
        "_slice_rows",
        lambda _window_days: [
            ("book_a", "5_TO_6_5", "MID_K", "R", "OVER", 50, 0.58, 0.6, 0.22),
            ("book_b", "GT_6_5", "HIGH_K", "L", "UNDER", 42, 0.55, 0.58, 0.23),
            ("book_c", "LT_5", "LOW_K", "R", "OVER", 48, 0.57, 0.59, 0.21),
        ],
    )

    result = strikeout_quality_service.strikeout_weekly_trust_report(
        {
            "driftMinSample": 40,
            "calibrationGapHard": 0.05,
        }
    )

    assert result["available"] is True
    assert result["publishable"] is True
    assert result["weekly"][0]["sportsbook"] == "book_a"
    assert result["regimeSplits"]["fallback"][0]["regime"] == "fallback_heavy"
    assert result["crossBookValidation"]["reliabilityReady"] is True
