import pytest

from services.nhl_strength_state_service import (
    EVEN,
    POWER_PLAY,
    SHIFT_TYPE_CODE,
    SHORT_HANDED,
    Shift,
    StrengthSegment,
    classify_segment,
    ice_time_by_strength,
    parse_shifts,
    strength_segments,
    strength_stats,
)

HOME = "21"
AWAY = "23"


def _shift_row(player_id, team_id, period, start, end, type_code=SHIFT_TYPE_CODE):
    return {
        "playerId": player_id,
        "teamId": team_id,
        "period": period,
        "startTime": start,
        "endTime": end,
        "typeCode": type_code,
    }


def _five(team, start, end, first=0):
    return [
        Shift(player_id=f"{team}-{first + index}", team_id=team, start=start, end=end)
        for index in range(5)
    ]


def test_only_real_shifts_are_parsed() -> None:
    rows = [
        _shift_row("1", HOME, 1, "01:22", "02:09"),
        # Goal and period markers share the feed and carry no duration.
        _shift_row("1", HOME, 1, "05:00", "05:00", type_code=505),
    ]
    shifts = parse_shifts(rows)

    assert len(shifts) == 1
    assert shifts[0].start == 82 and shifts[0].end == 129


def test_periods_become_absolute_game_seconds() -> None:
    shifts = parse_shifts([_shift_row("1", HOME, 2, "00:30", "01:00")])
    # Second period starts twenty minutes in.
    assert shifts[0].start == 1200 + 30


def test_zero_length_and_malformed_shifts_are_dropped() -> None:
    assert parse_shifts([_shift_row("1", HOME, 1, "05:00", "05:00")]) == []
    assert parse_shifts([_shift_row("", HOME, 1, "01:00", "02:00")]) == []
    assert parse_shifts([_shift_row("1", HOME, "x", "01:00", "02:00")]) == []


def test_equal_skaters_is_even_strength() -> None:
    segment = StrengthSegment(start=0, end=60, skaters_by_team={HOME: 5, AWAY: 5})
    assert classify_segment(segment, HOME) == EVEN
    assert classify_segment(segment, AWAY) == EVEN


def test_the_side_with_more_skaters_is_on_the_power_play() -> None:
    segment = StrengthSegment(start=0, end=60, skaters_by_team={HOME: 5, AWAY: 4})
    assert classify_segment(segment, HOME) == POWER_PLAY
    assert classify_segment(segment, AWAY) == SHORT_HANDED


def test_goaltenders_are_excluded_from_the_count() -> None:
    # A goalie is on the ice almost continuously; counting them would make
    # every segment look even.
    shifts = _five(HOME, 0, 120) + _five(AWAY, 0, 120)[:4] + [
        Shift(player_id="goalie", team_id=AWAY, start=0, end=120)
    ]
    segments = strength_segments(shifts, goalie_ids=frozenset({"goalie"}))

    assert len(segments) == 1
    assert segments[0].skaters_by_team == {HOME: 5, AWAY: 4}
    assert classify_segment(segments[0], HOME) == POWER_PLAY


def test_a_penalty_window_produces_power_play_and_shorthanded_time() -> None:
    # Two minutes at five-on-four, then two minutes back at even strength.
    shifts = (
        _five(HOME, 0, 240)
        + _five(AWAY, 0, 120)[:4]
        + _five(AWAY, 120, 240)
    )
    split = ice_time_by_strength(shifts)

    on_power_play = split[f"{HOME}-0"]
    assert on_power_play.power_play == pytest.approx(2.0, abs=1e-3)
    assert on_power_play.even == pytest.approx(2.0, abs=1e-3)

    killing = split[f"{AWAY}-0"]
    assert killing.short_handed == pytest.approx(2.0, abs=1e-3)


def test_split_reconciles_with_each_players_total_ice_time() -> None:
    # The property verified against a real game: the three states sum to the
    # total the box score reports.
    shifts = (
        _five(HOME, 0, 300)
        + _five(AWAY, 0, 100)[:4]
        + _five(AWAY, 100, 300)
    )
    split = ice_time_by_strength(shifts)

    for player_id, ice_time in split.items():
        played = sum(
            shift.duration for shift in shifts if shift.player_id == player_id
        )
        assert ice_time.total == pytest.approx(played / 60.0, abs=1e-3)


def test_no_shifts_yields_no_segments_rather_than_an_error() -> None:
    assert strength_segments([], goalie_ids=frozenset()) == []
    assert ice_time_by_strength([]) == {}


def test_stats_use_the_names_the_projection_layer_reads() -> None:
    shifts = _five(HOME, 0, 120) + _five(AWAY, 0, 120)
    stats = strength_stats(ice_time_by_strength(shifts)[f"{HOME}-0"])

    assert set(stats) == {
        "even_time_on_ice",
        "power_play_time_on_ice",
        "short_handed_time_on_ice",
    }
    assert stats["even_time_on_ice"] == pytest.approx(2.0, abs=1e-3)
