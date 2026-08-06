from math import exp

import pytest

from services.nhl_projection_service import (
    STRENGTH_STATES,
    SituationIceTime,
    SituationShotRates,
    project_goalie_saves,
    project_points,
    project_shots_on_goal,
)


def test_shots_split_by_strength_state_and_sum_to_the_total() -> None:
    projection = project_shots_on_goal(
        ice_time=SituationIceTime(even=14.0, power_play=3.5, short_handed=1.0),
        rates=SituationShotRates(
            even_attempts_per_minute=.25,
            power_play_attempts_per_minute=.45,
            short_handed_attempts_per_minute=.10,
        ),
    )

    assert projection.shots_on_goal == pytest.approx(
        projection.even + projection.power_play + projection.short_handed,
        abs=1e-3,
    )
    assert len(STRENGTH_STATES) == 3


def test_power_play_minutes_are_worth_more_than_even_strength_ones() -> None:
    rates = SituationShotRates(
        even_attempts_per_minute=.25, power_play_attempts_per_minute=.45,
    )
    demoted = project_shots_on_goal(
        ice_time=SituationIceTime(even=17.5, power_play=0.0), rates=rates,
    )
    promoted = project_shots_on_goal(
        ice_time=SituationIceTime(even=14.0, power_play=3.5), rates=rates,
    )

    # Identical total ice time; only the power-play role differs.
    assert demoted.shots_on_goal < promoted.shots_on_goal


def test_opponent_suppression_scales_the_whole_total() -> None:
    ice_time = SituationIceTime(even=16.0, power_play=3.0)
    rates = SituationShotRates(
        even_attempts_per_minute=.3, power_play_attempts_per_minute=.5,
    )
    neutral = project_shots_on_goal(ice_time=ice_time, rates=rates)
    suppressed = project_shots_on_goal(
        ice_time=ice_time, rates=rates, opponent_factor=.88,
    )
    assert suppressed.shots_on_goal < neutral.shots_on_goal
    # Extreme inputs cannot produce an absurd projection.
    assert project_shots_on_goal(
        ice_time=ice_time, rates=rates, opponent_factor=9.0,
    ).opponent_factor == 1.25


def test_on_goal_rate_is_separate_from_attempt_rate() -> None:
    ice_time = SituationIceTime(even=16.0)
    blocked = project_shots_on_goal(
        ice_time=ice_time,
        rates=SituationShotRates(
            even_attempts_per_minute=.4, even_on_goal_rate=.40
        ),
    )
    clean = project_shots_on_goal(
        ice_time=ice_time,
        rates=SituationShotRates(
            even_attempts_per_minute=.4, even_on_goal_rate=.65
        ),
    )
    assert blocked.shots_on_goal < clean.shots_on_goal


def test_points_separate_the_shooter_from_the_playmaker() -> None:
    shooter = project_points(
        expected_shots=4.0, shooting_percentage=.12,
        team_expected_goals_on_ice=1.4, assist_participation=.25,
    )
    playmaker = project_points(
        expected_shots=1.5, shooting_percentage=.08,
        team_expected_goals_on_ice=1.4, assist_participation=.70,
    )

    assert shooter.goals > playmaker.goals
    assert playmaker.assists > shooter.assists
    assert shooter.points == pytest.approx(shooter.goals + shooter.assists, abs=1e-5)


def test_a_player_cannot_assist_his_own_goal() -> None:
    # The team's on-ice expectation is reduced by the player's own goals
    # before assist participation applies.
    hog = project_points(
        expected_shots=10.0, shooting_percentage=.14,
        team_expected_goals_on_ice=1.4, assist_participation=1.0,
    )
    assert hog.assists == pytest.approx(max(0.0, 1.4 - hog.goals), abs=1e-5)


def test_any_point_probability_uses_the_poisson_rate() -> None:
    projection = project_points(
        expected_shots=3.0, shooting_percentage=.10,
        team_expected_goals_on_ice=1.2, assist_participation=.40,
    )
    assert projection.any_point_probability == pytest.approx(
        1 - exp(-projection.points), abs=1e-5
    )
    assert projection.any_point_probability < 1


def test_saves_follow_shots_against_times_save_percentage() -> None:
    projection = project_goalie_saves(
        opponent_shot_volume=31.0, expected_save_percentage=.910,
    )
    assert projection.saves == pytest.approx(31.0 * .910, abs=1e-3)


def test_a_suppressing_defence_lowers_saves_by_lowering_shots() -> None:
    exposed = project_goalie_saves(opponent_shot_volume=33.0)
    protected = project_goalie_saves(
        opponent_shot_volume=33.0, team_suppression_factor=.88,
    )
    assert protected.shots_against < exposed.shots_against
    assert protected.saves < exposed.saves


def test_a_likely_pull_reduces_the_shots_a_goalie_faces() -> None:
    full_game = project_goalie_saves(opponent_shot_volume=30.0)
    pulled = project_goalie_saves(
        opponent_shot_volume=30.0, pull_probability=1.0,
    )
    assert pulled.shots_against < full_game.shots_against
    assert pulled.pull_adjusted is True
    assert full_game.pull_adjusted is False
