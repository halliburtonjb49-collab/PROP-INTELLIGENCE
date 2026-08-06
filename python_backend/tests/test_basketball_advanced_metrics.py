from services.basketball_advanced_metrics_service import (
    BoxScoreLine,
    pace_per_game,
    possessions_used,
    team_game_possessions,
    three_point_form,
    usage_profile,
    usage_without_teammates,
)


def _line(player, minutes, **kwargs) -> BoxScoreLine:
    return BoxScoreLine(
        player=player, team_id="T1", game_id=kwargs.pop("game_id", "G1"),
        minutes=minutes, **kwargs
    )


def test_possessions_follow_the_standard_definition() -> None:
    line = _line(
        "Star", 34, field_goals_attempted=20, free_throw_attempts=6,
        turnovers=3, offensive_rebounds=2,
    )
    # 20 + .44*6 - 2 + 3
    assert possessions_used(line) == 23.64


def test_possessions_are_unavailable_without_shooting_detail() -> None:
    assert possessions_used(_line("Unknown", 30, turnovers=2)) is None


def test_offensive_rebounds_extend_rather_than_end_a_possession() -> None:
    crashing = _line("Crasher", 30, field_goals_attempted=10, offensive_rebounds=4)
    passive = _line("Spacer", 30, field_goals_attempted=10, offensive_rebounds=0)
    assert possessions_used(crashing) < possessions_used(passive)


def test_team_totals_aggregate_only_lines_with_detail() -> None:
    lines = [
        _line("A", 30, field_goals_attempted=15, turnovers=2),
        _line("B", 30, field_goals_attempted=10, turnovers=1),
        _line("C", 20),  # no shooting detail; must not be counted as zero
    ]
    totals = team_game_possessions(lines)
    assert set(totals) == {("G1", "T1")}
    total = totals[("G1", "T1")]
    assert total.players == 2
    assert total.possessions == 28.0
    assert total.minutes == 60.0


def test_pace_is_standardised_to_each_league_game_length() -> None:
    lines = [
        _line("A", 40, field_goals_attempted=40, turnovers=10),
        _line("B", 40, field_goals_attempted=40, turnovers=10),
        _line("C", 40, field_goals_attempted=40, turnovers=10),
        _line("D", 40, field_goals_attempted=40, turnovers=10),
        _line("E", 40, field_goals_attempted=40, turnovers=10),
    ]
    totals = list(team_game_possessions(lines).values())
    nba = pace_per_game(totals, sport="NBA")
    wnba = pace_per_game(totals, sport="WNBA")

    assert nba is not None and wnba is not None
    # The same possessions over a shorter game is a lower per-game pace.
    assert wnba < nba
    assert round(wnba / nba, 3) == round(40 / 48, 3)
    assert pace_per_game(totals, sport="NFL") is None


def test_usage_is_a_share_of_the_team_not_a_raw_count() -> None:
    team = [
        _line("Star", 36, field_goals_attempted=25, turnovers=4),
        _line("Role", 36, field_goals_attempted=5, turnovers=1),
    ]
    totals = team_game_possessions(team)
    star = usage_profile([team[0]], totals)
    role = usage_profile([team[1]], totals)

    assert star is not None and role is not None
    assert star.usage_rate > role.usage_rate
    assert 0 < role.usage_rate < 1
    assert star.shot_attempts_per_minute > role.shot_attempts_per_minute


def test_usage_weights_by_minutes_not_by_appearance() -> None:
    lines = [
        _line("Star", 36, game_id="G1", field_goals_attempted=24, turnovers=3),
        _line("Star", 2, game_id="G2", field_goals_attempted=3, turnovers=0),
        _line("Other", 36, game_id="G1", field_goals_attempted=6, turnovers=1),
        _line("Other", 36, game_id="G2", field_goals_attempted=6, turnovers=1),
    ]
    totals = team_game_possessions(lines)
    star = usage_profile([l for l in lines if l.player == "Star"], totals)

    assert star is not None
    # Averaging per-game rates would let the 2-minute cameo (1.5 attempts per
    # minute) drag the rate far above the true 24-over-36 workload.
    assert star.shot_attempts_per_minute < 0.8


def test_attempt_rates_describe_how_possessions_are_spent() -> None:
    lines = [
        _line(
            "Shooter", 30, field_goals_attempted=20, three_point_attempts=12,
            free_throw_attempts=4, turnovers=2,
        ),
    ]
    totals = team_game_possessions(lines)
    profile = usage_profile(lines, totals)

    assert profile is not None
    assert profile.three_point_attempt_rate == 0.6
    assert profile.free_throw_rate == 0.2


def test_three_point_form_needs_attempts_not_just_makes() -> None:
    with_attempts = three_point_form([
        _line("Shooter", 30, threes=4, three_point_attempts=10),
    ])
    assert with_attempts is not None
    assert with_attempts.made == 4 and with_attempts.attempted == 10
    assert with_attempts.attempts_per_minute == round(10 / 30, 5)

    # Makes alone cannot produce a percentage; inventing a denominator would
    # fabricate the certainty the beta-binomial exists to avoid.
    assert three_point_form([_line("Shooter", 30, threes=4)]) is None


def test_usage_splits_by_whether_a_teammate_played() -> None:
    lines = [
        # G1 and G2: the ball-handler plays. G3: they do not.
        _line("Star", 36, game_id="G1", field_goals_attempted=10, turnovers=2),
        _line("Handler", 36, game_id="G1", field_goals_attempted=20, turnovers=3),
        _line("Star", 36, game_id="G2", field_goals_attempted=10, turnovers=2),
        _line("Handler", 36, game_id="G2", field_goals_attempted=20, turnovers=3),
        _line("Star", 36, game_id="G3", field_goals_attempted=26, turnovers=4),
        _line("Filler", 36, game_id="G3", field_goals_attempted=4, turnovers=1),
    ]
    totals = team_game_possessions(lines)

    without, alongside = usage_without_teammates(
        lines, totals, player="Star", absent_players=["Handler"],
    )

    assert without is not None and alongside is not None
    # With the handler out, the star absorbs the vacated possessions.
    assert without.usage_rate > alongside.usage_rate


def test_usage_share_stays_within_bounds_for_a_full_lineup() -> None:
    # A realistic five-man team: shares must be fractions, and the starters'
    # shares must sum to roughly one across the whole lineup.
    lineup = [
        _line("A", 48, field_goals_attempted=20, turnovers=3),
        _line("B", 48, field_goals_attempted=15, turnovers=2),
        _line("C", 48, field_goals_attempted=12, turnovers=2),
        _line("D", 48, field_goals_attempted=10, turnovers=1),
        _line("E", 48, field_goals_attempted=8, turnovers=1),
    ]
    totals = team_game_possessions(lineup)
    shares = []
    for line in lineup:
        profile = usage_profile([line], totals)
        assert profile is not None
        assert 0 < profile.usage_rate < 1
        shares.append(profile.usage_rate)

    # Every possession belongs to someone, so the lineup's shares total one.
    assert round(sum(shares), 3) == 1.0


def test_three_point_market_projects_from_stored_attempts() -> None:
    from services.basketball_advanced_metrics_service import (
        project_three_pointers_from_logs,
    )

    lines = [
        _line("Shooter", 30, game_id=f"G{i}", threes=2, three_point_attempts=6)
        for i in range(10)
    ]
    projection = project_three_pointers_from_logs(
        lines, minutes=32, league_percentage=.36,
    )

    assert projection is not None
    assert projection.attempts == round(32 * (60 / 300), 3)
    # 20 of 60 is .333; the league prior pulls it up toward .36 without
    # reaching it.
    assert .333 < projection.percentage < .36


def test_three_point_market_declines_to_project_without_attempts() -> None:
    from services.basketball_advanced_metrics_service import (
        project_three_pointers_from_logs,
    )

    lines = [_line("Shooter", 30, threes=3) for _ in range(10)]
    assert project_three_pointers_from_logs(
        lines, minutes=30, league_percentage=.36,
    ) is None
