from types import SimpleNamespace

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
