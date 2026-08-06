from services.basketball_projection_service import (
    LEAGUE_PARAMETERS,
    MinutesContext,
    league_parameters,
    per_minute_rate,
    project_minutes,
    project_stat,
    project_three_pointers,
    simulate_points_rebounds_assists,
)


def test_leagues_share_architecture_but_not_parameters() -> None:
    nba = league_parameters("NBA")
    wnba = league_parameters("WNBA")

    assert nba is not None and wnba is not None
    assert wnba.regulation_minutes == 40 and nba.regulation_minutes == 48
    # No constant may be silently shared: a forty-minute game cannot use
    # forty-eight-minute rotation thresholds.
    assert wnba.maximum_minutes < nba.maximum_minutes
    assert wnba.starter_minutes < nba.starter_minutes
    assert wnba.rotation_change_minutes < nba.rotation_change_minutes
    assert league_parameters("NFL") is None


def test_minutes_lead_recent_rotation_rather_than_trailing_it() -> None:
    promoted = project_minutes([18, 17, 19, 18, 20, 31, 33, 32], sport="NBA")

    assert promoted is not None
    assert promoted.role_change == "EXPANDED"
    assert "rotation" in promoted.adjustments
    # A trailing average would still be dragged down by the bench stretch.
    assert promoted.minutes > sum([18, 17, 19, 18, 20, 31, 33, 32]) / 8


def test_minutes_never_exceed_what_the_league_allows() -> None:
    absurd = project_minutes([47, 47, 47, 47, 47], sport="WNBA")

    assert absurd is not None
    assert absurd.minutes <= LEAGUE_PARAMETERS["WNBA"].maximum_minutes


def test_minutes_apply_only_the_components_that_have_inputs() -> None:
    bare = project_minutes([30, 31, 29, 30, 32], sport="NBA")
    assert bare is not None
    assert bare.applied == ()

    informed = project_minutes(
        [30, 31, 29, 30, 32],
        sport="NBA",
        context=MinutesContext(
            is_back_to_back=True,
            game_spread=20.0,
            absent_starters=1,
        ),
    )
    assert informed is not None
    assert set(informed.applied) >= {"rest", "spread", "injuries"}
    assert informed.adjustments["rest"] < 0
    assert informed.adjustments["spread"] < 0
    assert informed.adjustments["injuries"] > 0


def test_blowout_and_back_to_back_reduce_minutes() -> None:
    neutral = project_minutes(
        [32, 33, 31, 32, 33], sport="NBA",
        context=MinutesContext(game_spread=2.0, is_back_to_back=False),
    )
    punished = project_minutes(
        [32, 33, 31, 32, 33], sport="NBA",
        context=MinutesContext(game_spread=22.0, is_back_to_back=True),
    )
    assert neutral is not None and punished is not None
    assert punished.minutes < neutral.minutes


def test_short_logs_produce_no_minutes_projection() -> None:
    assert project_minutes([30, 31], sport="NBA") is None


def test_per_minute_rate_weights_by_minutes_not_by_game() -> None:
    # A two-minute cameo with one point is not a 0.5 per-minute scorer.
    rate = per_minute_rate([20, 22, 21, 1], [32, 34, 33, 2])
    assert rate is not None
    assert .55 < rate.rate < .70


def test_thin_minute_samples_shrink_toward_the_peer_rate() -> None:
    thin = per_minute_rate([12], [10], prior_rate=.50)
    deep = per_minute_rate([12] * 20, [10] * 20, prior_rate=.50)

    assert thin is not None and deep is not None
    assert thin.shrunk_from == deep.shrunk_from == 1.2
    assert thin.own_weight < deep.own_weight
    assert thin.rate < deep.rate


def test_projection_decomposes_into_opportunity_and_rate() -> None:
    # Same rate, more minutes, more production -- the property a per-game
    # average cannot express.
    assert project_stat(minutes=36, rate=0.7) == project_stat(
        minutes=18, rate=0.7
    ) * 2
    assert project_stat(minutes=30, rate=0.8, pace_factor=1.05) > project_stat(
        minutes=30, rate=0.8
    )
    assert project_stat(minutes=30, rate=0.8, defense_factor=0.9) < project_stat(
        minutes=30, rate=0.8
    )


def test_pra_is_simulated_jointly_not_summed_independently() -> None:
    minutes = project_minutes([32, 33, 31, 34, 32, 33], sport="NBA")
    assert minutes is not None
    joint = simulate_points_rebounds_assists(
        minutes=minutes,
        points_rate=.75,
        rebounds_rate=.20,
        assists_rate=.15,
        sport="NBA",
    )

    assert joint.pra == round(
        joint.points + joint.rebounds + joint.assists, 3
    )
    # The components share a minutes draw, so the total's spread is wider than
    # any single component's and reflects that shared driver.
    pra_width = joint.pra_interval[1] - joint.pra_interval[0]
    points_width = joint.points_interval[1] - joint.points_interval[0]
    assert pra_width > points_width


def test_joint_simulation_is_reproducible() -> None:
    minutes = project_minutes([30, 30, 30, 30, 30], sport="WNBA")
    assert minutes is not None
    kwargs = dict(
        minutes=minutes, points_rate=.6, rebounds_rate=.25,
        assists_rate=.12, sport="WNBA",
    )
    assert simulate_points_rebounds_assists(**kwargs) == (
        simulate_points_rebounds_assists(**kwargs)
    )


def test_three_point_percentage_is_pulled_toward_the_league_rate() -> None:
    # Eight of twelve is not a 67% shooter.
    hot = project_three_pointers(
        minutes=30, attempts_per_minute=.2,
        made=8, attempted=12, league_percentage=.36,
    )
    assert .36 < hot.percentage < .45

    # A full season of the same rate earns far more of its own weight.
    established = project_three_pointers(
        minutes=30, attempts_per_minute=.2,
        made=200, attempted=300, league_percentage=.36,
    )
    assert established.percentage > hot.percentage


def test_three_point_projection_is_attempts_times_percentage() -> None:
    projection = project_three_pointers(
        minutes=30, attempts_per_minute=.25,
        made=36, attempted=100, league_percentage=.36,
    )
    assert projection.attempts == 7.5
    assert projection.made == round(7.5 * projection.percentage, 4)
    # Evidence exactly on the prior leaves the prior unmoved.
    assert projection.percentage == 0.36
