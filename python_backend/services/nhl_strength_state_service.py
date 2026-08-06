"""Skater ice time split by strength state, derived from shift charts.

A power-play minute and an even-strength minute produce shots at very
different rates, so a single time-on-ice total hides the change that matters
most when a player's role moves. The box score only reports the total.

Strength state is derived from the shifts themselves rather than from penalty
records. Every shift says who was on the ice and when, so counting the
skaters each team had on at a given moment states the strength directly:
five against five is even, five against four is a power play for the side
with five. Reading it this way needs no penalty parsing and cannot disagree
with the shift data, because it is the shift data.

Goaltenders are excluded from the counts. They are on the ice almost
continuously, and including them would make every segment look even.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Mapping, Sequence

# The NHL shift feed marks real shifts with this type. Other rows are goal and
# period markers that carry no duration.
SHIFT_TYPE_CODE = 517

REGULATION_PERIOD_SECONDS = 1200

EVEN = "even"
POWER_PLAY = "power_play"
SHORT_HANDED = "short_handed"


def _seconds_from_clock(value: object) -> int | None:
    text = str(value if value is not None else "").strip()
    if ":" not in text:
        return None
    minutes, _, seconds = text.partition(":")
    try:
        return (int(minutes) * 60) + int(seconds)
    except ValueError:
        return None


@dataclass(frozen=True)
class Shift:
    player_id: str
    team_id: str
    start: int
    end: int

    @property
    def duration(self) -> int:
        return max(0, self.end - self.start)


def parse_shifts(rows: Iterable[Mapping[str, object]]) -> list[Shift]:
    """Shift rows to absolute-second intervals, ignoring non-shift markers."""

    shifts: list[Shift] = []
    for row in rows:
        if not isinstance(row, Mapping) or row.get("typeCode") != SHIFT_TYPE_CODE:
            continue
        period = row.get("period")
        start = _seconds_from_clock(row.get("startTime"))
        end = _seconds_from_clock(row.get("endTime"))
        player_id = str(row.get("playerId") or "").strip()
        team_id = str(row.get("teamId") or "").strip()
        if start is None or end is None or not player_id or not team_id:
            continue
        try:
            offset = (int(period) - 1) * REGULATION_PERIOD_SECONDS
        except (TypeError, ValueError):
            continue
        if end <= start:
            continue
        shifts.append(
            Shift(
                player_id=player_id,
                team_id=team_id,
                start=offset + start,
                end=offset + end,
            )
        )
    return shifts


@dataclass(frozen=True)
class StrengthSegment:
    start: int
    end: int
    skaters_by_team: Mapping[str, int]

    @property
    def duration(self) -> int:
        return max(0, self.end - self.start)


def strength_segments(
    shifts: Sequence[Shift],
    *,
    goalie_ids: frozenset[str],
) -> list[StrengthSegment]:
    """Split the game at every substitution and count skaters in each piece.

    The boundaries are every shift start and end, so within one segment the
    players on the ice never change and a single skater count describes it.
    """

    skater_shifts = [shift for shift in shifts if shift.player_id not in goalie_ids]
    if not skater_shifts:
        return []
    boundaries = sorted(
        {shift.start for shift in skater_shifts}
        | {shift.end for shift in skater_shifts}
    )
    segments: list[StrengthSegment] = []
    for start, end in zip(boundaries, boundaries[1:]):
        if end <= start:
            continue
        counts: dict[str, int] = {}
        for shift in skater_shifts:
            if shift.start <= start and shift.end >= end:
                counts[shift.team_id] = counts.get(shift.team_id, 0) + 1
        if counts:
            segments.append(
                StrengthSegment(start=start, end=end, skaters_by_team=counts)
            )
    return segments


def classify_segment(segment: StrengthSegment, team_id: str) -> str:
    """Even, power play or shorthanded from one team's point of view."""

    own = segment.skaters_by_team.get(team_id, 0)
    opposing = [
        count for team, count in segment.skaters_by_team.items() if team != team_id
    ]
    if not opposing:
        return EVEN
    other = max(opposing)
    if own > other:
        return POWER_PLAY
    if own < other:
        return SHORT_HANDED
    return EVEN


@dataclass(frozen=True)
class StrengthIceTime:
    even: float
    power_play: float
    short_handed: float

    @property
    def total(self) -> float:
        return round(self.even + self.power_play + self.short_handed, 4)


def ice_time_by_strength(
    shifts: Sequence[Shift],
    *,
    goalie_ids: frozenset[str] = frozenset(),
) -> dict[str, StrengthIceTime]:
    """Minutes per strength state for every skater in the game.

    Returned in minutes rather than seconds because every downstream rate is
    per minute.
    """

    segments = strength_segments(shifts, goalie_ids=goalie_ids)
    if not segments:
        return {}
    totals: dict[str, dict[str, float]] = {}
    for segment in segments:
        for shift in shifts:
            if shift.player_id in goalie_ids:
                continue
            overlap = min(shift.end, segment.end) - max(shift.start, segment.start)
            if overlap <= 0:
                continue
            state = classify_segment(segment, shift.team_id)
            bucket = totals.setdefault(
                shift.player_id, {EVEN: 0.0, POWER_PLAY: 0.0, SHORT_HANDED: 0.0}
            )
            bucket[state] += overlap
    return {
        player_id: StrengthIceTime(
            even=round(values[EVEN] / 60.0, 4),
            power_play=round(values[POWER_PLAY] / 60.0, 4),
            short_handed=round(values[SHORT_HANDED] / 60.0, 4),
        )
        for player_id, values in totals.items()
    }


def strength_stats(ice_time: StrengthIceTime) -> dict[str, float]:
    """Canonical stat names for storage alongside the box-score fields."""

    return {
        "even_time_on_ice": ice_time.even,
        "power_play_time_on_ice": ice_time.power_play,
        "short_handed_time_on_ice": ice_time.short_handed,
    }
