from services.projection_backtest_service import (
    grade_market,
    summarize,
    walk_forward,
)


def _mean(values):
    return sum(values) / len(values)


def test_a_game_is_never_projected_from_itself() -> None:
    """Leakage would make any model look perfect and grade nothing."""

    seen: list[int] = []

    def project(past):
        seen.append(len(past))
        return _mean(past)

    history = list(range(20))
    results = walk_forward(history, project=project)

    assert results
    # Every projection saw strictly fewer games than the index it predicted.
    assert all(count < len(history) for count in seen)


def test_a_short_history_is_not_graded() -> None:
    # The first projections would report the cold start, not the model.
    assert walk_forward([1, 2, 3], project=_mean) == []


def test_a_market_measured_correctly_shows_little_bias() -> None:
    history = [10, 12, 11, 13, 9, 12, 10, 11, 12, 10, 11, 12]
    grade = grade_market("WNBA", "player_points", [history], project=_mean)

    assert grade is not None
    assert abs(grade.bias) < 1.5
    assert grade.suspect is False


def test_the_wrong_statistic_shows_up_as_bias_not_noise() -> None:
    """The defect this exists to catch.

    A fantasy line projected from raw points is not noisy, it is confidently
    low on every single game -- which is exactly what the board did.
    """

    fantasy = [36, 38, 41, 33, 39, 37, 40, 35, 38, 36, 39, 37]

    # Projecting points (~14) against fantasy outcomes (~37).
    grade = grade_market(
        "WNBA", "player_fantasy_points", [fantasy], project=lambda past: 14.0
    )

    assert grade is not None
    assert grade.bias < 0
    assert grade.suspect is True
    assert abs(grade.bias_ratio) >= 0.5


def test_an_overprojected_market_is_caught_too() -> None:
    # Power-play points projected from total scoring: confidently high.
    power_play = [0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0]
    grade = grade_market(
        "NHL", "player_power_play_points", [power_play], project=lambda past: 2.4
    )

    assert grade is not None
    assert grade.bias > 0
    assert grade.suspect is True


def test_the_baseline_is_what_complexity_has_to_beat() -> None:
    history = [10, 12, 11, 13, 9, 12, 10, 11, 12, 10, 11, 12]

    # A projection that simply is the running mean cannot beat the mean.
    grade = grade_market("WNBA", "player_points", [history], project=_mean)
    assert grade is not None
    assert grade.beat_baseline_rate == 0.0
    assert grade.improves_on_baseline is False


def test_the_report_leads_with_what_is_broken() -> None:
    good = grade_market("WNBA", "player_points", [[10] * 14], project=lambda p: 10.0)
    bad = grade_market(
        "WNBA", "player_fantasy_points", [[37] * 14], project=lambda p: 14.0
    )
    report = summarize([good, bad])

    assert report["marketsSuspect"] == 1
    assert report["suspectMarkets"][0]["market"] == "player_fantasy_points"
    # Suspect markets sort to the front of the full list too.
    assert report["markets"][0]["market"] == "player_fantasy_points"
    assert "different question" in report["verdict"]


def test_a_clean_report_says_so_plainly() -> None:
    good = grade_market("WNBA", "player_points", [[10] * 14], project=lambda p: 10.0)

    assert "no market looks like" in summarize([good])["verdict"]


def test_a_market_with_no_usable_history_is_not_invented() -> None:
    assert grade_market("NFL", "player_sacks", [[1, 2]], project=_mean) is None
