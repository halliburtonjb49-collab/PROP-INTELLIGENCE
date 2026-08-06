from math import exp

import pytest

from services.nfl_projection_service import (
    expected_catch_rate,
    project_pass_attempts,
    project_passing_yards,
    project_receiving,
    project_routes,
    project_rushing_yards,
    project_team_plays,
    project_touchdowns,
    script_pass_rate_shift,
    touchdown_market_is_actionable,
)


def test_shared_clock_averages_pace_rather_than_compounding_it() -> None:
    fast_vs_slow = project_team_plays(neutral_pace=70, opponent_pace=56)
    # Both offences share one game clock, so the result lands between them.
    assert fast_vs_slow == 63.0
    assert fast_vs_slow < 70


def test_game_script_moves_the_two_sides_in_opposite_directions() -> None:
    favourite = script_pass_rate_shift(spread=7, is_favourite=True)
    underdog = script_pass_rate_shift(spread=7, is_favourite=False)

    assert favourite < 0 < underdog
    assert favourite == -underdog


def test_script_shift_is_capped_for_lopsided_spreads() -> None:
    # A four-score underdog still runs occasionally.
    assert script_pass_rate_shift(spread=28, is_favourite=False) == 0.09
    assert script_pass_rate_shift(spread=3, is_favourite=False) < 0.09


def test_pass_attempts_split_plays_by_rate_and_leave_the_rest_to_the_run() -> None:
    volume = project_pass_attempts(plays=64, neutral_pass_rate=.58)

    assert volume.pass_attempts == pytest.approx(37.12)
    assert volume.rush_attempts == pytest.approx(64 - 37.12)
    assert volume.pass_attempts + volume.rush_attempts == pytest.approx(64)


def test_trailing_teams_throw_more_than_leading_ones() -> None:
    trailing = project_pass_attempts(
        plays=64, neutral_pass_rate=.58, spread=10, is_favourite=False,
    )
    leading = project_pass_attempts(
        plays=64, neutral_pass_rate=.58, spread=10, is_favourite=True,
    )
    assert trailing.pass_attempts > leading.pass_attempts


def test_pass_rate_over_expectation_shifts_the_baseline() -> None:
    neutral = project_pass_attempts(plays=64, neutral_pass_rate=.58)
    aggressive = project_pass_attempts(
        plays=64, neutral_pass_rate=.58, pass_rate_over_expectation=.05,
    )
    assert aggressive.pass_attempts > neutral.pass_attempts


def test_passing_yards_chain_attempts_through_completion_and_depth() -> None:
    assert project_passing_yards(
        attempts=35, completion_probability=.65, yards_per_completion=11.5,
    ) == pytest.approx(35 * .65 * 11.5)


def test_routes_come_from_dropbacks_and_participation() -> None:
    assert project_routes(dropbacks=40, route_participation=.85) == 34.0
    # A receiver on the field for half the dropbacks has half the chances.
    assert project_routes(dropbacks=40, route_participation=.5) == 20.0


def test_receiving_chains_routes_through_targets_and_catches() -> None:
    projection = project_receiving(
        routes=34, targets_per_route=.22, catch_probability=.68,
        yards_per_reception=12.5,
    )

    # Values are rounded to three decimals for display, so compare at that
    # resolution rather than to full float precision.
    assert projection.targets == pytest.approx(7.48, abs=1e-3)
    assert projection.receptions == pytest.approx(7.48 * .68, abs=1e-3)
    assert projection.yards == pytest.approx(projection.receptions * 12.5, abs=1e-2)


def test_targets_per_route_is_independent_of_how_often_the_team_throws() -> None:
    # The same involvement in a pass-heavy and a run-heavy offence yields
    # different totals through routes, not through a changed rate.
    heavy = project_receiving(
        routes=45, targets_per_route=.22, catch_probability=.68,
        yards_per_reception=12.0,
    )
    light = project_receiving(
        routes=28, targets_per_route=.22, catch_probability=.68,
        yards_per_reception=12.0,
    )
    assert heavy.targets_per_route == light.targets_per_route
    assert heavy.yards > light.yards


def test_catch_rate_from_a_small_sample_stays_near_the_role_rate() -> None:
    # Four of five is not an 80% receiver.
    small = expected_catch_rate(receptions=4, targets=5, role_catch_rate=.65)
    assert .65 < small < .70

    large = expected_catch_rate(receptions=80, targets=100, role_catch_rate=.65)
    assert large > small


def test_rushing_adds_scrambles_outside_the_designed_carry_pool() -> None:
    designed_only = project_rushing_yards(
        team_rush_attempts=26, carry_share=.62, yards_per_carry=4.4,
    )
    with_scrambles = project_rushing_yards(
        team_rush_attempts=26, carry_share=.62, yards_per_carry=4.4,
        scramble_carries=3,
    )
    assert designed_only == pytest.approx(26 * .62 * 4.4)
    assert with_scrambles > designed_only


def test_touchdown_probability_follows_the_poisson_form() -> None:
    projection = project_touchdowns(
        red_zone_opportunities=3.0, conversion_rate=.18,
    )
    assert projection.expected_touchdowns == pytest.approx(.54)
    assert projection.any_touchdown_probability == pytest.approx(
        1 - exp(-.54), abs=1e-5
    )
    # A rate above zero can never be a certainty.
    assert projection.any_touchdown_probability < 1


def test_scoring_channels_convert_at_their_own_rates() -> None:
    # A goal-line carry is not a red-zone target and must not share its rate.
    combined = project_touchdowns(
        red_zone_opportunities=2, conversion_rate=.12,
        goal_line_carries=1.5, goal_line_conversion_rate=.45,
        end_zone_targets=1.0, end_zone_conversion_rate=.30,
    )
    assert combined.expected_touchdowns == pytest.approx(
        2 * .12 + 1.5 * .45 + 1.0 * .30
    )


def test_touchdown_markets_require_a_higher_bar() -> None:
    # An edge that would pass on a yardage market is inside the noise here.
    assert touchdown_market_is_actionable(
        model_probability=.60, market_probability=.52,
    ) is False
    assert touchdown_market_is_actionable(
        model_probability=.66, market_probability=.63,
    ) is False
    assert touchdown_market_is_actionable(
        model_probability=.66, market_probability=.55,
    ) is True
    assert touchdown_market_is_actionable(
        model_probability=.70, market_probability=None,
    ) is False
