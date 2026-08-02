from services.wowy_usage_service import UsageTotals, analyze_wowy_usage, usage_rate


def totals(*, player_fga: float, player_minutes: float) -> UsageTotals:
    return UsageTotals(
        player_fga=player_fga,
        player_fta=20,
        player_tov=10,
        player_minutes=player_minutes,
        team_fga=400,
        team_fta=100,
        team_tov=60,
        team_minutes=player_minutes * 5,
    )


def test_standard_usage_formula() -> None:
    value = usage_rate(totals(player_fga=100, player_minutes=200))
    assert value is not None
    assert round(value, 2) == 23.57


def test_wowy_delta_is_reliability_shrunk_and_bounded() -> None:
    result = analyze_wowy_usage(
        totals(player_fga=80, player_minutes=300),
        totals(player_fga=140, player_minutes=300),
    )
    assert result["actionable"] is True
    assert result["offUsagePercentage"] > result["onUsagePercentage"]
    assert result["direction"] == "OVER_CONTEXT"
    assert 1 < result["projectionMultiplier"] <= 1.08


def test_small_wowy_sample_cannot_adjust_a_pick() -> None:
    result = analyze_wowy_usage(
        totals(player_fga=25, player_minutes=80),
        totals(player_fga=50, player_minutes=80),
    )
    assert result["actionable"] is False
    assert result["direction"] == "INSUFFICIENT_SAMPLE"
    assert result["projectionMultiplier"] == 1
