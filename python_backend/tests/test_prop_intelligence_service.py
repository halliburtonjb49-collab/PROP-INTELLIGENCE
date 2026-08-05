from services.prop_intelligence_service import analyze_prop


def test_analyze_prop_recommends_over_when_model_edge_is_positive() -> None:
    result = analyze_prop(
        player="Ava",
        sport="NBA",
        market="player_points",
        line=22.5,
        projected_mean=24.0,
        projected_std_dev=4.0,
        sharp_over_odds=1.91,
        sharp_under_odds=1.91,
        retail_over_odds=2.05,
        retail_under_odds=1.80,
        bankroll=1000,
        kelly_fraction=0.25,
        simulations=200,
        seed=42,
    )

    assert result["recommendation"] == "OVER"
    assert result["modelOverProbability"] > 0.5
    assert result["suggestedWagerUsd"] > 0
    assert result["expectedValuePercent"] > 0


def test_analyze_prop_returns_pass_when_no_edge_exists() -> None:
    result = analyze_prop(
        player="Ava",
        sport="NBA",
        market="player_points",
        line=22.5,
        projected_mean=22.5,
        projected_std_dev=0.1,
        sharp_over_odds=1.91,
        sharp_under_odds=1.91,
        retail_over_odds=1.91,
        retail_under_odds=1.91,
        bankroll=1000,
        kelly_fraction=0.25,
        simulations=200,
        seed=7,
    )

    assert result["recommendation"] == "PASS"
    assert result["expectedValuePercent"] <= 0


def test_analyze_prop_uses_mlb_strikeout_log5_path() -> None:
    result = analyze_prop(
        player="Pitcher",
        sport="MLB",
        market="Pitcher Strikeouts",
        line=6.5,
        projected_mean=8.0,
        projected_std_dev=2.0,
        sharp_over_odds=1.95,
        sharp_under_odds=1.87,
        pitches_per_start=95,
        pitches_per_batter=3.9,
        pitcher_k_pct=0.30,
        lineup_k_pct=0.25,
        temp_f=55,
        umpire_k_boost=0.015,
        park_k_factor=1.03,
    )

    assert result["method"] == "mlb_strikeout_log5_binomial"
    assert result["projectedBattersFaced"] > 0
    assert 0 < result["matchupKRate"] < 1
    assert result["recommendation"] in {"OVER", "UNDER", "PASS"}
