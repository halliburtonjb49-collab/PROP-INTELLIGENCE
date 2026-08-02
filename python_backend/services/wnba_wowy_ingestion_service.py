"""Substitution-aware WNBA play-by-play aggregation for WOWY usage.

Inputs use the column names returned by ``PlayByPlayV2`` and
``BoxScoreTraditionalV2``. Network retrieval is intentionally separate so the
stint reconstruction remains deterministic, testable, and cache friendly.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass

from services.wowy_usage_service import UsageTotals, analyze_wowy_usage


@dataclass
class _Accumulator:
    player_fga: float = 0
    player_fta: float = 0
    player_tov: float = 0
    player_minutes: float = 0
    team_fga: float = 0
    team_fta: float = 0
    team_tov: float = 0
    team_minutes: float = 0

    def totals(self) -> UsageTotals:
        return UsageTotals(**self.__dict__)


def _period_length_seconds(period: int) -> int:
    return 600 if period <= 4 else 300


def _clock_seconds(raw: object) -> int | None:
    value = str(raw or "").strip()
    if not value or ":" not in value:
        return None
    try:
        minutes, seconds = value.split(":", 1)
        return int(minutes) * 60 + int(float(seconds))
    except (TypeError, ValueError):
        return None


def starting_lineups(
    box_rows: Iterable[Mapping[str, object]],
) -> dict[int, set[int]]:
    lineups: dict[int, set[int]] = {}
    for row in box_rows:
        if not str(row.get("START_POSITION") or "").strip():
            continue
        try:
            team_id = int(row["TEAM_ID"])
            player_id = int(row["PLAYER_ID"])
        except (KeyError, TypeError, ValueError):
            continue
        lineups.setdefault(team_id, set()).add(player_id)
    return {team: players for team, players in lineups.items() if len(players) == 5}


def aggregate_wowy_game(
    play_by_play: Iterable[Mapping[str, object]],
    *,
    initial_lineups: Mapping[int, set[int]],
    team_id: int,
    player_id: int,
    teammate_id: int,
) -> tuple[UsageTotals, UsageTotals]:
    """Return target-player totals with teammate ON and OFF for one game."""
    active = {int(team): set(players) for team, players in initial_lineups.items()}
    if len(active.get(team_id, set())) != 5:
        raise ValueError("A verified five-player starting lineup is required.")
    on = _Accumulator()
    off = _Accumulator()
    previous_period = 1
    previous_clock = _period_length_seconds(1)

    rows = sorted(
        play_by_play,
        key=lambda row: int(row.get("EVENTNUM") or 0),
    )
    for row in rows:
        period = int(row.get("PERIOD") or previous_period)
        clock = _clock_seconds(row.get("PCTIMESTRING"))
        if period != previous_period:
            previous_period = period
            previous_clock = _period_length_seconds(period)
        if clock is not None:
            elapsed = max(0, previous_clock - clock)
            team_lineup = active.get(team_id, set())
            if player_id in team_lineup:
                bucket = on if teammate_id in team_lineup else off
                bucket.player_minutes += elapsed / 60
                bucket.team_minutes += elapsed * 5 / 60
            previous_clock = clock

        event_type = int(row.get("EVENTMSGTYPE") or 0)
        event_player = int(row.get("PLAYER1_ID") or 0)
        event_team = int(row.get("PLAYER1_TEAM_ID") or 0)
        team_lineup = active.get(team_id, set())
        if player_id in team_lineup:
            bucket = on if teammate_id in team_lineup else off
            if event_team == team_id:
                if event_type in {1, 2}:
                    bucket.team_fga += 1
                    if event_player == player_id:
                        bucket.player_fga += 1
                elif event_type == 3:
                    bucket.team_fta += 1
                    if event_player == player_id:
                        bucket.player_fta += 1
                elif event_type == 5:
                    bucket.team_tov += 1
                    if event_player == player_id:
                        bucket.player_tov += 1

        if event_type == 8:
            out_id = int(row.get("PLAYER1_ID") or 0)
            in_id = int(row.get("PLAYER2_ID") or 0)
            substitution_team = int(
                row.get("PLAYER1_TEAM_ID") or row.get("PLAYER2_TEAM_ID") or 0
            )
            lineup = active.setdefault(substitution_team, set())
            if out_id:
                lineup.discard(out_id)
            if in_id:
                lineup.add(in_id)

    return on.totals(), off.totals()


def analyze_wowy_games(
    games: Iterable[
        tuple[Iterable[Mapping[str, object]], Mapping[int, set[int]]]
    ],
    *,
    team_id: int,
    player_id: int,
    teammate_id: int,
    minimum_split_minutes: float = 100,
) -> dict[str, object]:
    combined_on = _Accumulator()
    combined_off = _Accumulator()
    games_used = 0
    for play_by_play, lineups in games:
        on, off = aggregate_wowy_game(
            play_by_play,
            initial_lineups=lineups,
            team_id=team_id,
            player_id=player_id,
            teammate_id=teammate_id,
        )
        for field in combined_on.__dict__:
            setattr(combined_on, field, getattr(combined_on, field) + getattr(on, field))
            setattr(combined_off, field, getattr(combined_off, field) + getattr(off, field))
        games_used += 1
    return {
        **analyze_wowy_usage(
            combined_on.totals(),
            combined_off.totals(),
            minimum_split_minutes=minimum_split_minutes,
        ),
        "gamesUsed": games_used,
        "source": "WNBA PlayByPlayV2 + BoxScoreTraditionalV2",
        "leagueId": "10",
    }

