from services.wnba_wowy_ingestion_service import (
    aggregate_wowy_game,
    starting_lineups,
)
from services.wowy_usage_service import usage_rate


TEAM = 10
TARGET = 1
TEAMMATE = 2


def event(number, kind, clock, player=0, team=0, player2=0):
    return {
        "EVENTNUM": number,
        "EVENTMSGTYPE": kind,
        "PERIOD": 1,
        "PCTIMESTRING": clock,
        "PLAYER1_ID": player,
        "PLAYER1_TEAM_ID": team,
        "PLAYER2_ID": player2,
        "PLAYER2_TEAM_ID": team,
    }


def test_starting_lineups_require_box_score_starters() -> None:
    rows = [
        {"TEAM_ID": TEAM, "PLAYER_ID": player, "START_POSITION": "G"}
        for player in range(1, 6)
    ] + [{"TEAM_ID": TEAM, "PLAYER_ID": 6, "START_POSITION": ""}]
    assert starting_lineups(rows) == {TEAM: {1, 2, 3, 4, 5}}


def test_play_by_play_separates_target_usage_when_teammate_exits() -> None:
    rows = [
        event(1, 2, "09:00", TARGET, TEAM),
        event(2, 2, "09:00", TEAMMATE, TEAM),
        event(3, 8, "08:00", TEAMMATE, TEAM, 6),
        event(4, 1, "07:00", TARGET, TEAM),
        event(5, 2, "07:00", 3, TEAM),
        event(6, 5, "06:00", TARGET, TEAM),
    ]
    on, off = aggregate_wowy_game(
        rows,
        initial_lineups={TEAM: {1, 2, 3, 4, 5}},
        team_id=TEAM,
        player_id=TARGET,
        teammate_id=TEAMMATE,
    )

    assert on.player_minutes == 2
    assert off.player_minutes == 2
    assert on.player_fga == 1
    assert off.player_fga == 1
    assert off.player_tov == 1
    assert usage_rate(off) > usage_rate(on)


def test_target_bench_minutes_do_not_enter_either_split() -> None:
    rows = [
        event(1, 8, "09:00", TARGET, TEAM, 6),
        event(2, 1, "08:00", 3, TEAM),
    ]
    on, off = aggregate_wowy_game(
        rows,
        initial_lineups={TEAM: {1, 2, 3, 4, 5}},
        team_id=TEAM,
        player_id=TARGET,
        teammate_id=TEAMMATE,
    )
    assert on.player_minutes == 1
    assert off.player_minutes == 0
    assert on.team_fga == 0
