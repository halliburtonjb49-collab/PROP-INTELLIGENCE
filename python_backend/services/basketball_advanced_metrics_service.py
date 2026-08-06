"""Usage, shot rate and possession metrics derived from stored box scores.

None of this needs a new provider. The ingestion already captures the full
box-score row, so possessions, usage and attempt rates are arithmetic on data
that is present -- they were simply never computed.

Two conventions used throughout:

    possessions = FGA + 0.44 * FTA - OREB + TOV
    usage       = player possessions / team possessions, per minute of the
                  team's available minutes

The 0.44 weights free-throw trips, since only some free throws end a
possession. Usage needs the team's totals, so it is computed per team-game
rather than per player -- a player's share is meaningless without the whole.
"""

from __future__ import annotations

from dataclasses import dataclass
from statistics import fmean
from typing import Iterable, Mapping, Sequence

from services.basketball_projection_service import (
    ThreePointProjection,
    league_parameters,
    project_three_pointers,
)

# Share of free-throw attempts that end a possession. The standard weight;
# two-shot trips dominate, and-ones and technicals pull it below 0.5.
FREE_THROW_POSSESSION_WEIGHT = 0.44

# Players on the floor at once, used to convert team minutes to team
# possessions per game.
PLAYERS_ON_COURT = 5


@dataclass(frozen=True)
class BoxScoreLine:
    """One player's game, with the fields advanced metrics need."""

    player: str
    team_id: str
    game_id: str
    minutes: float
    points: float = 0.0
    rebounds: float = 0.0
    assists: float = 0.0
    turnovers: float = 0.0
    field_goals_attempted: float | None = None
    field_goals_made: float | None = None
    three_point_attempts: float | None = None
    threes: float = 0.0
    free_throw_attempts: float = 0.0
    offensive_rebounds: float | None = None
    defensive_rebounds: float | None = None


def possessions_used(line: BoxScoreLine) -> float | None:
    """Possessions a player consumed. None when shooting detail is absent."""

    if line.field_goals_attempted is None:
        return None
    used = (
        float(line.field_goals_attempted)
        + (FREE_THROW_POSSESSION_WEIGHT * float(line.free_throw_attempts or 0))
        + float(line.turnovers or 0)
    )
    if line.offensive_rebounds is not None:
        # An offensive rebound continues the possession rather than ending it.
        used -= float(line.offensive_rebounds)
    return max(0.0, used)


@dataclass(frozen=True)
class TeamGamePossessions:
    team_id: str
    game_id: str
    possessions: float
    minutes: float
    players: int


def team_game_possessions(
    lines: Iterable[BoxScoreLine],
) -> dict[tuple[str, str], TeamGamePossessions]:
    """Aggregate a set of player lines into team-game possession totals."""

    totals: dict[tuple[str, str], list[float]] = {}
    for line in lines:
        used = possessions_used(line)
        if used is None:
            continue
        key = (str(line.game_id), str(line.team_id))
        bucket = totals.setdefault(key, [0.0, 0.0, 0.0])
        bucket[0] += used
        bucket[1] += max(0.0, float(line.minutes or 0))
        bucket[2] += 1
    return {
        key: TeamGamePossessions(
            team_id=key[1],
            game_id=key[0],
            possessions=round(value[0], 3),
            minutes=round(value[1], 2),
            players=int(value[2]),
        )
        for key, value in totals.items()
    }


def pace_per_game(
    team_totals: Sequence[TeamGamePossessions],
    *,
    sport: str,
) -> float | None:
    """Possessions standardised to one full game of the league's length.

    Standardising matters because a team's raw possession count depends on how
    many minutes were played -- overtime inflates it. A WNBA game is forty
    minutes, so its possessions are normalised against forty, not forty-eight.
    """

    parameters = league_parameters(sport)
    if parameters is None or not team_totals:
        return None
    rates = []
    for total in team_totals:
        if total.minutes <= 0:
            continue
        per_minute = total.possessions / (total.minutes / PLAYERS_ON_COURT)
        rates.append(per_minute * parameters.regulation_minutes)
    return round(fmean(rates), 3) if rates else None


@dataclass(frozen=True)
class UsageProfile:
    usage_rate: float
    possessions_per_minute: float
    shot_attempts_per_minute: float
    three_point_attempt_rate: float
    free_throw_rate: float
    sample_minutes: float
    games: int


def usage_profile(
    lines: Sequence[BoxScoreLine],
    team_totals: Mapping[tuple[str, str], TeamGamePossessions],
) -> UsageProfile | None:
    """A player's share of their team's possessions, and how they spend them.

    Computed from summed totals rather than averaged per-game rates, so a
    two-minute appearance cannot weigh as much as a full game.
    """

    player_possessions = 0.0
    player_minutes = 0.0
    attempts = 0.0
    three_attempts = 0.0
    free_throws = 0.0
    games = 0
    # Usage is the standard share:
    #     (player possessions * team minutes / 5) / (player minutes * team
    #      possessions)
    # The team-minutes term converts the team's whole-game possession count to
    # the rate a single player on the floor would face. Numerator and
    # denominator are pooled across games rather than averaging per-game
    # shares, so a short appearance cannot swing the season rate.
    usage_numerator = 0.0
    usage_denominator = 0.0

    for line in lines:
        used = possessions_used(line)
        minutes = max(0.0, float(line.minutes or 0))
        if used is None or minutes <= 0:
            continue
        team = team_totals.get((str(line.game_id), str(line.team_id)))
        if team is None or team.minutes <= 0 or team.possessions <= 0:
            continue
        player_possessions += used
        player_minutes += minutes
        usage_numerator += used * (team.minutes / PLAYERS_ON_COURT)
        usage_denominator += minutes * team.possessions
        attempts += float(line.field_goals_attempted or 0)
        three_attempts += (
            float(line.three_point_attempts)
            if line.three_point_attempts is not None
            else 0.0
        )
        free_throws += float(line.free_throw_attempts or 0)
        games += 1

    if games == 0 or player_minutes <= 0 or usage_denominator <= 0:
        return None

    return UsageProfile(
        usage_rate=round(usage_numerator / usage_denominator, 5),
        possessions_per_minute=round(player_possessions / player_minutes, 5),
        shot_attempts_per_minute=round(attempts / player_minutes, 5),
        three_point_attempt_rate=round(three_attempts / attempts, 5) if attempts else 0.0,
        free_throw_rate=round(free_throws / attempts, 5) if attempts else 0.0,
        sample_minutes=round(player_minutes, 1),
        games=games,
    )


@dataclass(frozen=True)
class ThreePointForm:
    attempts_per_minute: float
    made: float
    attempted: float


def three_point_form(lines: Sequence[BoxScoreLine]) -> ThreePointForm | None:
    """Three-point volume and the make/attempt evidence for the beta prior.

    Returns None when attempts were never recorded: without a denominator the
    percentage cannot be estimated, and inferring one from makes alone would
    invent the very uncertainty the beta-binomial exists to represent.
    """

    minutes = 0.0
    attempts = 0.0
    made = 0.0
    observed_attempts = False
    for line in lines:
        played = max(0.0, float(line.minutes or 0))
        if played <= 0:
            continue
        minutes += played
        made += float(line.threes or 0)
        if line.three_point_attempts is not None:
            attempts += float(line.three_point_attempts)
            observed_attempts = True
    if minutes <= 0 or not observed_attempts or attempts <= 0:
        return None
    return ThreePointForm(
        attempts_per_minute=round(attempts / minutes, 5),
        made=round(made, 1),
        attempted=round(attempts, 1),
    )


def usage_without_teammates(
    lines: Sequence[BoxScoreLine],
    team_totals: Mapping[tuple[str, str], TeamGamePossessions],
    *,
    player: str,
    absent_players: Sequence[str],
) -> tuple[UsageProfile | None, UsageProfile | None]:
    """Usage split by whether given teammates played, for a WOWY comparison.

    A player's role changes when the ball-handler beside them sits, which a
    blended season rate cannot express. Pass every line for the team, not just
    the subject's: which games a teammate played is only visible in theirs.

    Returns (without those teammates, alongside them); either side is None
    when no games fall in it.
    """

    absent = {str(name).strip().lower() for name in absent_players if name}
    subject_name = str(player).strip().lower()
    games_teammate_played = {
        str(line.game_id)
        for line in lines
        if str(line.player).strip().lower() in absent
        and float(line.minutes or 0) > 0
    }
    subject = [
        line for line in lines if str(line.player).strip().lower() == subject_name
    ]
    without = [
        line for line in subject if str(line.game_id) not in games_teammate_played
    ]
    alongside = [
        line for line in subject if str(line.game_id) in games_teammate_played
    ]
    return (
        usage_profile(without, team_totals),
        usage_profile(alongside, team_totals),
    )


def project_three_pointers_from_logs(
    lines: Sequence[BoxScoreLine],
    *,
    minutes: float,
    league_percentage: float,
) -> ThreePointProjection | None:
    """Volume and percentage for a three-point market, from stored box scores.

    Bridges the attempt data to the beta-binomial projection, which cannot be
    used without a denominator. Returns None when attempts were never
    recorded, so the caller falls back rather than projecting on a percentage
    that was never observed.
    """

    form = three_point_form(lines)
    if form is None:
        return None
    return project_three_pointers(
        minutes=minutes,
        attempts_per_minute=form.attempts_per_minute,
        made=form.made,
        attempted=form.attempted,
        league_percentage=league_percentage,
    )
