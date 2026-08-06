from types import SimpleNamespace

from pytest import approx

from services import prop_context_service
from services.projection_calibration_service import (
    DEFAULT_RECENCY_WEIGHTS,
    ProjectionContext,
    calibrated_hit_probability,
    contextual_projection,
    exponentially_weighted_mean,
    recency_weighted_baseline,
    shrink_toward_prior,
    shrinkage_weight,
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


def test_recency_baseline_leads_recent_form_without_discarding_the_long_run() -> None:
    values = ([10] * 20) + ([20] * 5)
    baseline = recency_weighted_baseline(values)

    assert sum(values) / len(values) < baseline < 20
    # The last five games are the only ones at 20, so they lift the baseline by
    # their share of each window and no further.
    assert baseline == approx(
        10 + (10 * (0.40 + (0.25 / 2) + (0.20 / 4) + (0.15 / 5)))
    )


def test_recency_baseline_stays_inside_the_observed_range() -> None:
    values = [3, 9, 1, 12, 7, 4, 8, 2]
    assert min(values) <= recency_weighted_baseline(values) <= max(values)
    assert sum(DEFAULT_RECENCY_WEIGHTS) == approx(1)


def test_recency_baseline_handles_logs_shorter_than_every_window() -> None:
    # Windows overlap completely, so a three-game log is just its own mean.
    assert recency_weighted_baseline([4, 5, 6]) == approx(5)


def test_shrinkage_gives_the_player_more_weight_as_games_accumulate() -> None:
    assert shrinkage_weight(0, k=8) == 0
    assert shrinkage_weight(8, k=8) == .5
    assert shrinkage_weight(40, k=8) > .8


def test_two_hot_games_cannot_carry_a_projection() -> None:
    hot, weight = shrink_toward_prior(34.0, 18.0, sample_size=2, k=8)

    assert weight == approx(.2)
    assert hot == approx(21.2)

    settled, settled_weight = shrink_toward_prior(34.0, 18.0, sample_size=40, k=8)
    assert settled_weight > weight
    assert settled > hot


def test_shrinkage_is_skipped_when_no_prior_describes_the_role() -> None:
    assert shrink_toward_prior(12.5, None, sample_size=3) == (12.5, 1.0)


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


def test_strikeout_release_gate_suppresses_fallback_heavy_pick(
    monkeypatch,
    recently_observed,
) -> None:
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
            "observedAt": recently_observed(),
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


def test_probability_edge_is_measured_against_the_no_vig_market() -> None:
    prop = SimpleNamespace(
        projection=6.4,
        line=5.5,
        injuryStatus="healthy",
        lineupStatus="confirmed",
        projectionVolatility=1.5,
        projectionSampleSize=25,
        projectionCalibrated=True,
        historicalHitRate=None,
        sport="MLB",
        market="Pitcher Strikeouts",
        noVigOverProbability=.52,
        noVigUnderProbability=.48,
        overDecimalOdds=1.91,
        underDecimalOdds=1.91,
        recommendationAvailable=True,
    )

    apply_projection_context(prop)

    assert prop.marketProbability == .52
    assert prop.probabilityEdge == approx(
        prop.modelProbability - .52, abs=1e-6
    )
    # The stat-unit edge and the probability edge are different quantities.
    assert prop.probabilityEdge != prop.projection - prop.line


def test_probability_edge_is_absent_without_a_priced_market() -> None:
    prop = SimpleNamespace(
        projection=6.4,
        line=5.5,
        injuryStatus="healthy",
        lineupStatus="confirmed",
        projectionVolatility=1.5,
        projectionSampleSize=25,
        projectionCalibrated=True,
        historicalHitRate=None,
        sport="MLB",
        market="Pitcher Strikeouts",
        recommendationAvailable=True,
    )

    apply_projection_context(prop)

    assert prop.probabilityEdge is None
