from types import SimpleNamespace

from services import prop_context_service
from services.projection_calibration_service import (
    ProjectionContext,
    calibrated_hit_probability,
    contextual_projection,
    exponentially_weighted_mean,
)
from services.prop_context_service import apply_projection_context


def test_probability_uses_market_volatility_and_sample_shrinkage() -> None:
    small = calibrated_hit_probability(
        projection=6,
        line=4,
        volatility=.4,
        side="OVER",
        sample_size=8,
        sport="MLB",
        market="Pitcher Strikeouts",
    )
    mature = calibrated_hit_probability(
        projection=6,
        line=4,
        volatility=.4,
        side="OVER",
        sample_size=40,
        sport="MLB",
        market="Pitcher Strikeouts",
    )
    assert .5 < small < mature <= .8


def test_exponential_average_responds_to_recent_form_without_discarding_history() -> None:
    values = [2, 2, 2, 2, 2, 8, 8, 8]
    weighted = exponentially_weighted_mean(values)
    assert sum(values) / len(values) < weighted < 8


def test_context_multiplier_is_bounded() -> None:
    assert contextual_projection(
        10,
        ProjectionContext(workload_multiplier=.5, opponent_multiplier=.5),
    ) == 6.5
    assert contextual_projection(
        10,
        ProjectionContext(workload_multiplier=2, opponent_multiplier=2),
    ) == 13.5


def test_prop_context_recalculates_projection_probability_and_side() -> None:
    prop = SimpleNamespace(
        projection=5.5,
        line=5,
        injuryStatus="questionable",
        lineupStatus="confirmed",
        fatigueMultiplier=.95,
        matchupMultiplier=1.1,
        projectionVolatility=1.5,
        projectionSampleSize=20,
        historicalHitRate=60,
        sport="NBA",
        market="Points",
        recommendationAvailable=True,
    )
    apply_projection_context(prop)
    assert prop.projection != 5.5
    assert .5 <= prop.fairProbability <= .8
    assert prop.recommendedSide == "N/A"
    assert prop.opportunityStatus == "SYSTEM_LEAN"
    assert "injury_status_unresolved" in prop.opportunityReasons


def test_prop_context_shrinks_uncertain_projection_to_multi_book_market() -> None:
    prop = SimpleNamespace(
        projection=30,
        line=24,
        marketOriginLine=24,
        marketBookCount=5,
        injuryStatus="healthy",
        lineupStatus="confirmed",
        projectionVolatility=4.5,
        projectionSampleSize=0,
        projectionCalibrated=False,
        historicalHitRate=None,
        sport="NBA",
        market="Points",
        recommendationAvailable=True,
    )

    apply_projection_context(prop)

    assert prop.projectionPreMarket == 30
    assert prop.projectionMarketWeight == .3
    assert prop.projection == 28.2


def test_missing_sample_metadata_does_not_overwrite_verified_tier() -> None:
    prop = SimpleNamespace(
        projection=6.2,
        line=5.5,
        injuryStatus="healthy",
        lineupStatus="confirmed",
        projectionVolatility=1.45,
        projectionSampleSize=0,
        projectionCalibrated=False,
        historicalHitRate=None,
        sport="NBA",
        market="Points",
        recommendationAvailable=True,
        confidence=62,
        tier="Strong",
    )

    apply_projection_context(prop)

    assert prop.confidence == 0
    assert prop.tier == "No Pick"
    assert prop.recommendationAvailable is False
    assert "insufficient_projection_sample" in prop.opportunityReasons
    assert prop.pick == "N/A"


def test_strikeout_release_gate_suppresses_fallback_heavy_pick(monkeypatch) -> None:
    monkeypatch.setattr(
        prop_context_service,
        "analyze_prop",
        lambda **_: {
            "recommendation": "OVER",
            "confidence": 72,
            "expectedValuePercent": 6.1,
            "edgePercent": 6.1,
            "usedFallbackPitcherRate": True,
            "usedFallbackLineupRate": False,
            "usedFallbackTbf": False,
            "usedMarketBlend": True,
            "method": "mlb_strikeout_log5_binomial",
            "skillSource": "k_rate_log5",
            "projectedBattersFaced": 24,
            "marketWeight": 0.2,
            "modelOverProbability": 0.61,
            "marketOverProbability": 0.58,
        },
    )
    prop = SimpleNamespace(
        projection=6.5,
        line=5.5,
        injuryStatus="healthy",
        lineupStatus="confirmed",
        projectionVolatility=1.4,
        projectionSampleSize=20,
        projectionCalibrated=True,
        historicalHitRate=None,
        sport="MLB",
        market="Pitcher Strikeouts",
        marketKey="pitcher_strikeouts",
        category="STRIKEOUTS",
        recommendationAvailable=True,
        mlbProjectedLineupMatchup={
            "confirmed": True,
            "observedAt": "2026-08-05T18:10:00Z",
                "opposingLineup": [
                    {"player": f"Batter {idx}", "battingOrder": idx}
                    for idx in range(1, 10)
                ],
        },
        pitcherKPercent=None,
        pitcherCsw=None,
        pitchesPerStart=95.0,
        pitchesPerBatter=3.9,
        lineupKPercent=0.24,
        lineupCswAgainst=None,
        temperatureF=65.0,
        umpireKBoost=0.01,
        parkKFactor=1.0,
        overDecimalOdds=1.91,
        underDecimalOdds=1.91,
    )

    apply_projection_context(prop)

    assert prop.recommendationAvailable is False
    assert prop.recommendationUnavailableReason == "strikeout_fallback_over_limit"
    assert prop.pick == "N/A"
    assert prop.confidence == 0
