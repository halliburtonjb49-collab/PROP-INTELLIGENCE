"""Minutes-and-chance projections for soccer player props.

Soccer's defining feature for props is that playing time is not given. A
starter may be withdrawn on the hour, a substitute may get twenty minutes,
and both outcomes are decided by the score and the fixture list rather than
by the player. Expected minutes therefore comes first and everything scales
from it.

Competition is a first-class input, never an afterthought. Premier League
parameters do not describe MLS, a Champions League tie or an international
fixture, so every function takes the competition and no default silently
applies one league's behaviour to another.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import exp
from typing import Mapping

FULL_MATCH_MINUTES = 90


@dataclass(frozen=True)
class CompetitionProfile:
    """Per-competition behaviour that must not be shared across leagues."""

    name: str
    # Minutes a withdrawn starter typically loses, and how often it happens.
    early_substitution_minutes: float
    starter_substitution_rate: float
    # Minutes a substitute typically receives when introduced.
    substitute_minutes: float
    # Added time, which varies by competition and by how strictly it is kept.
    expected_added_time: float
    league_shots_per_90: float
    league_on_target_rate: float


# Starting profiles only. Each is a hypothesis to be replaced by fitted values
# per competition; the point is that they are separate, not that they are
# right.
COMPETITION_PROFILES: Mapping[str, CompetitionProfile] = {
    "EPL": CompetitionProfile(
        name="Premier League",
        early_substitution_minutes=22.0,
        starter_substitution_rate=0.42,
        substitute_minutes=21.0,
        expected_added_time=6.5,
        league_shots_per_90=1.25,
        league_on_target_rate=0.34,
    ),
    "MLS": CompetitionProfile(
        name="Major League Soccer",
        # Heat, travel and a deeper substitution allowance mean starters are
        # withdrawn earlier and more often than in Europe.
        early_substitution_minutes=26.0,
        starter_substitution_rate=0.55,
        substitute_minutes=24.0,
        expected_added_time=6.0,
        league_shots_per_90=1.30,
        league_on_target_rate=0.33,
    ),
    "UCL": CompetitionProfile(
        name="Champions League",
        early_substitution_minutes=20.0,
        starter_substitution_rate=0.38,
        substitute_minutes=18.0,
        expected_added_time=6.0,
        league_shots_per_90=1.35,
        league_on_target_rate=0.35,
    ),
    "INTERNATIONAL": CompetitionProfile(
        name="International",
        # Managers rotate heavily in friendlies and qualifiers alike.
        early_substitution_minutes=30.0,
        starter_substitution_rate=0.62,
        substitute_minutes=26.0,
        expected_added_time=5.5,
        league_shots_per_90=1.20,
        league_on_target_rate=0.33,
    ),
}


def competition_profile(competition: str) -> CompetitionProfile | None:
    """Profile for a competition, or None when it has not been characterised.

    Returning None rather than a default is deliberate: projecting an
    uncharacterised competition with Premier League behaviour is the error
    this structure exists to prevent.
    """

    return COMPETITION_PROFILES.get(str(competition or "").strip().upper())


@dataclass(frozen=True)
class MinutesProjection:
    expected_minutes: float
    start_probability: float
    expected_early_substitution: float
    expected_added_time: float


def project_expected_minutes(
    *,
    competition: str,
    start_probability: float,
    congestion_factor: float = 1.0,
    is_doubtful: bool = False,
) -> MinutesProjection | None:
    """E[minutes] = 90 * P(start) - E[early substitution] + E[added time].

    A substitute's expected minutes are counted too: not starting is not the
    same as not playing, and the difference is most of the value in a shots
    market for a rotation forward.
    """

    profile = competition_profile(competition)
    if profile is None:
        return None

    starting = max(0.0, min(1.0, float(start_probability)))
    congestion = max(0.5, min(1.5, float(congestion_factor)))
    # A congested fixture list raises both how often a starter is withdrawn
    # and how early.
    substitution_rate = min(1.0, profile.starter_substitution_rate * congestion)
    if is_doubtful:
        substitution_rate = min(1.0, substitution_rate * 1.25)
    early_loss = (
        starting * substitution_rate * profile.early_substitution_minutes
    )
    as_substitute = (1.0 - starting) * profile.substitute_minutes
    added = starting * profile.expected_added_time
    expected = (FULL_MATCH_MINUTES * starting) - early_loss + as_substitute + added
    return MinutesProjection(
        expected_minutes=round(max(0.0, min(100.0, expected)), 3),
        start_probability=round(starting, 4),
        expected_early_substitution=round(early_loss, 3),
        expected_added_time=round(added, 3),
    )


@dataclass(frozen=True)
class ShotsProjection:
    shots: float
    shots_on_target: float
    per_90: float


def project_shots(
    *,
    expected_minutes: float,
    shots_per_90: float,
    on_target_rate: float,
    team_attack_factor: float = 1.0,
    opponent_factor: float = 1.0,
    role_factor: float = 1.0,
    shot_location_adjustment: float = 1.0,
) -> ShotsProjection:
    """Shots = minutes/90 * shots per 90 * team * opponent * role."""

    share = max(0.0, float(expected_minutes)) / FULL_MATCH_MINUTES
    shots = (
        share
        * max(0.0, float(shots_per_90))
        * float(team_attack_factor)
        * float(opponent_factor)
        * float(role_factor)
    )
    on_target = shots * max(0.0, min(1.0, float(on_target_rate))) * float(
        shot_location_adjustment
    )
    return ShotsProjection(
        shots=round(max(0.0, shots), 4),
        # Shots on target cannot exceed shots however the adjustments land.
        shots_on_target=round(max(0.0, min(shots, on_target)), 4),
        per_90=round(float(shots_per_90), 4),
    )


@dataclass(frozen=True)
class GoalsProjection:
    expected_goals: float
    any_goal_probability: float


def project_goals(
    *,
    expected_shots: float,
    expected_goals_per_shot: float,
) -> GoalsProjection:
    """E[goals] = sum of per-shot xG, then P(at least one) = 1 - exp(-E).

    Per-shot xG is used rather than a historical conversion rate because a
    striker's finishing over a season of forty shots is mostly noise, while
    the quality of the chances they get is a repeatable property of their role.
    """

    expected = max(0.0, float(expected_shots)) * max(
        0.0, min(1.0, float(expected_goals_per_shot))
    )
    return GoalsProjection(
        expected_goals=round(expected, 5),
        any_goal_probability=round(1.0 - exp(-expected), 5),
    )


def project_assists(
    *,
    expected_key_passes: float,
    chance_conversion_probability: float,
) -> GoalsProjection:
    """E[assists] = expected key passes * chance conversion.

    Built from chances created rather than assists recorded, since an assist
    depends on a teammate finishing and is therefore a noisier measure of the
    creator than the chances themselves.
    """

    expected = max(0.0, float(expected_key_passes)) * max(
        0.0, min(1.0, float(chance_conversion_probability))
    )
    return GoalsProjection(
        expected_goals=round(expected, 5),
        any_goal_probability=round(1.0 - exp(-expected), 5),
    )


def project_goalkeeper_saves(
    *,
    opponent_expected_shots_on_target: float,
    expected_save_rate: float,
) -> float:
    """Saves = opponent expected shots on target * expected save rate."""

    return round(
        max(0.0, float(opponent_expected_shots_on_target))
        * max(0.0, min(1.0, float(expected_save_rate))),
        4,
    )


def project_passes(
    *,
    expected_minutes: float,
    passes_per_minute: float,
    possession_factor: float = 1.0,
    pressing_factor: float = 1.0,
    game_state_factor: float = 1.0,
) -> float:
    """Passes = minutes * passes per minute * possession * pressing * state.

    Possession and pressing pull in opposite directions: a side that keeps the
    ball passes more, and one pressed hard passes less accurately and less
    often, so both belong in the projection rather than one standing for both.
    """

    return round(
        max(0.0, float(expected_minutes))
        * max(0.0, float(passes_per_minute))
        * float(possession_factor)
        * float(pressing_factor)
        * float(game_state_factor),
        3,
    )
