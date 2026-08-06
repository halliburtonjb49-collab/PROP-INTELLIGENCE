from math import exp

import pytest

from services.cricket_projection_service import (
    FORMAT_PROFILES,
    ODI,
    T20,
    TEST,
    format_profile,
    position_hazard_curve,
    project_batting,
    project_bowling,
    survival_curve,
)
from services.projection_calibration_service import parameter_keys
from services.soccer_projection_service import (
    competition_profile,
    project_assists,
    project_expected_minutes,
    project_goalkeeper_saves,
    project_goals,
    project_passes,
    project_shots,
)


# --- soccer -----------------------------------------------------------------


def test_competitions_do_not_share_behaviour() -> None:
    epl = competition_profile("EPL")
    mls = competition_profile("MLS")

    assert epl is not None and mls is not None
    # MLS withdraws starters earlier and more often than the Premier League.
    assert mls.starter_substitution_rate > epl.starter_substitution_rate
    assert mls.early_substitution_minutes > epl.early_substitution_minutes


def test_an_uncharacterised_competition_is_not_given_league_defaults() -> None:
    # Projecting an unknown competition with Premier League behaviour is the
    # error the structure exists to prevent.
    assert competition_profile("SOME_CUP") is None
    assert project_expected_minutes(
        competition="SOME_CUP", start_probability=1.0
    ) is None


def test_a_certain_starter_plays_close_to_a_full_match() -> None:
    minutes = project_expected_minutes(competition="EPL", start_probability=1.0)

    assert minutes is not None
    assert 80 < minutes.expected_minutes < 100
    assert minutes.expected_early_substitution > 0


def test_a_likely_substitute_still_earns_expected_minutes() -> None:
    # Not starting is not the same as not playing, and the difference is most
    # of the value in a shots market for a rotation forward.
    bench = project_expected_minutes(competition="EPL", start_probability=0.0)

    assert bench is not None
    assert bench.expected_minutes > 15


def test_congestion_and_doubt_reduce_expected_minutes() -> None:
    rested = project_expected_minutes(
        competition="EPL", start_probability=1.0, congestion_factor=1.0,
    )
    congested = project_expected_minutes(
        competition="EPL", start_probability=1.0, congestion_factor=1.4,
    )
    doubtful = project_expected_minutes(
        competition="EPL", start_probability=1.0, is_doubtful=True,
    )

    assert congested.expected_minutes < rested.expected_minutes
    assert doubtful.expected_minutes < rested.expected_minutes


def test_the_same_player_projects_differently_by_competition() -> None:
    epl = project_expected_minutes(competition="EPL", start_probability=1.0)
    mls = project_expected_minutes(competition="MLS", start_probability=1.0)
    assert mls.expected_minutes < epl.expected_minutes


def test_shots_scale_with_minutes_and_context() -> None:
    full = project_shots(
        expected_minutes=90, shots_per_90=2.4, on_target_rate=.38,
    )
    half = project_shots(
        expected_minutes=45, shots_per_90=2.4, on_target_rate=.38,
    )
    assert full.shots == pytest.approx(half.shots * 2, abs=1e-4)
    assert full.shots == pytest.approx(2.4, abs=1e-4)


def test_shots_on_target_can_never_exceed_shots() -> None:
    # However the location adjustment lands, the subset cannot exceed the set.
    projection = project_shots(
        expected_minutes=90, shots_per_90=3.0, on_target_rate=.9,
        shot_location_adjustment=5.0,
    )
    assert projection.shots_on_target <= projection.shots


def test_goals_use_chance_quality_and_a_poisson_tail() -> None:
    projection = project_goals(expected_shots=3.2, expected_goals_per_shot=.11)

    assert projection.expected_goals == pytest.approx(.352, abs=1e-4)
    assert projection.any_goal_probability == pytest.approx(
        1 - exp(-.352), abs=1e-4
    )
    assert projection.any_goal_probability < 1


def test_assists_come_from_chances_created_not_assists_recorded() -> None:
    projection = project_assists(
        expected_key_passes=2.5, chance_conversion_probability=.12,
    )
    assert projection.expected_goals == pytest.approx(.30, abs=1e-4)


def test_keeper_saves_follow_shots_faced() -> None:
    assert project_goalkeeper_saves(
        opponent_expected_shots_on_target=4.5, expected_save_rate=.71,
    ) == pytest.approx(3.195, abs=1e-3)


def test_possession_and_pressing_both_move_passes() -> None:
    base = project_passes(expected_minutes=90, passes_per_minute=.7)
    dominant = project_passes(
        expected_minutes=90, passes_per_minute=.7, possession_factor=1.2,
    )
    pressed = project_passes(
        expected_minutes=90, passes_per_minute=.7, pressing_factor=.85,
    )
    assert dominant > base > pressed


def test_parameters_resolve_competition_first_then_sport() -> None:
    keys = parameter_keys("SOCCER", "player shots", "EPL")
    assert keys == ("soccer epl player shots", "soccer player shots")
    # Without a competition there is only the sport-wide key.
    assert parameter_keys("SOCCER", "player shots") == ("soccer player shots",)


# --- cricket ----------------------------------------------------------------


def test_formats_are_separate_and_unknown_ones_are_refused() -> None:
    assert set(FORMAT_PROFILES) >= {"T20", "ODI", "TEST", "THE_HUNDRED"}
    # A Test innings priced on Twenty20 hazards would be nonsense.
    assert format_profile(TEST).base_dismissal_hazard < format_profile(
        T20
    ).base_dismissal_hazard
    assert format_profile(T20).base_runs_per_ball > format_profile(
        TEST
    ).base_runs_per_ball
    assert format_profile("BEACH_CRICKET") is None
    assert project_batting(
        match_format="BEACH_CRICKET", dismissal_hazards=[.03] * 30
    ) is None


def test_survival_is_a_running_product_not_a_single_rate() -> None:
    curve = survival_curve([.1, .1, .1])
    assert curve[0] == pytest.approx(.9, abs=1e-6)
    assert curve[1] == pytest.approx(.81, abs=1e-6)
    assert curve[2] == pytest.approx(.729, abs=1e-6)
    # Survival can only fall.
    assert curve == sorted(curve, reverse=True)


def test_expected_balls_is_an_output_of_survival_not_an_input() -> None:
    projection = project_batting(
        match_format=T20, dismissal_hazards=[.05] * 60, runs_per_ball=1.3,
    )
    assert projection is not None
    # A batter facing a 5% hazard cannot expect all sixty deliveries.
    assert projection.expected_balls < 60
    assert projection.expected_balls > 10
    assert projection.survival_to_end < .05


def test_a_higher_hazard_shortens_the_innings_and_the_score() -> None:
    safe = project_batting(
        match_format=ODI, dismissal_hazards=[.01] * 100, runs_per_ball=.9,
    )
    risky = project_batting(
        match_format=ODI, dismissal_hazards=[.06] * 100, runs_per_ball=.9,
    )
    assert risky.expected_balls < safe.expected_balls
    assert risky.expected_runs < safe.expected_runs


def test_new_batters_are_most_vulnerable_before_they_are_set() -> None:
    curve = position_hazard_curve(match_format=T20, balls=40, batting_position=3)
    assert curve is not None
    assert curve[0] > curve[-1]
    # The settling period ends and the hazard drops to its baseline.
    assert curve[5] > curve[20]


def test_lower_order_batters_carry_a_higher_hazard_throughout() -> None:
    opener = position_hazard_curve(match_format=T20, balls=30, batting_position=1)
    tail = position_hazard_curve(match_format=T20, balls=30, batting_position=9)
    assert tail[-1] > opener[-1]


def test_batting_position_changes_the_projection() -> None:
    top = project_batting(
        match_format=T20,
        dismissal_hazards=position_hazard_curve(
            match_format=T20, balls=60, batting_position=2
        ),
    )
    lower = project_batting(
        match_format=T20,
        dismissal_hazards=position_hazard_curve(
            match_format=T20, balls=60, batting_position=8
        ),
    )
    assert lower.expected_runs < top.expected_runs


def test_death_overs_are_not_powerplay_overs() -> None:
    powerplay = project_bowling(
        match_format=T20, expected_overs=4, wicket_probability_per_ball=.05,
        runs_allowed_per_ball=1.2, phase="powerplay",
    )
    death = project_bowling(
        match_format=T20, expected_overs=4, wicket_probability_per_ball=.05,
        runs_allowed_per_ball=1.2, phase="death",
    )

    assert death.expected_runs_conceded > powerplay.expected_runs_conceded
    # The death overs raise scoring far more than they raise wicket chances.
    runs_ratio = death.expected_runs_conceded / powerplay.expected_runs_conceded
    wicket_ratio = death.expected_wickets / powerplay.expected_wickets
    assert runs_ratio > wicket_ratio


def test_bowling_converts_overs_to_deliveries() -> None:
    projection = project_bowling(
        match_format=ODI, expected_overs=10, wicket_probability_per_ball=.03,
        runs_allowed_per_ball=.95, phase="middle",
    )
    assert projection.expected_balls == 60
