"""Whether a prop is fit to be shown, and fit to be selected.

A card that says "Player Points" for a baseball player, names the teams
CLEVELAND_GUARDIANS_MLB, and reports its source as UNKNOWN is not a display
problem. It is the feed telling us it does not know what this prop is, in
three separate ways, and the interface repeating it verbatim.

This module answers two questions the rest of the pipeline never asked:

    Is this prop internally coherent -- does its market exist in its sport,
    does it name a real event, does it come from a source we can name?

    Is it complete enough to act on -- is there a projection behind it, a
    line, a verified market?

The first failure means the prop should not be displayed at all. The second
means it can be displayed but must not be selectable, because a pick built on
an unverified prop is a pick built on nothing.

Nothing here guesses. A prop missing its market is not assigned a plausible
one; it is marked unverified and the reason is recorded, so the gap is
visible rather than papered over.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Iterable, Mapping

from services.market_config import SPORT_MARKETS

# Sport label to the provider's sport key, so a prop's market can be checked
# against the markets that sport actually has.
_SPORT_KEYS: Mapping[str, str] = {
    "NBA": "basketball_nba",
    "WNBA": "basketball_wnba",
    "MLB": "baseball_mlb",
    "NFL": "americanfootball_nfl",
    "NHL": "icehockey_nhl",
}

# League suffixes the odds feeds append to team identifiers.
_LEAGUE_SUFFIXES = (
    "MLB", "NBA", "WNBA", "NFL", "NHL", "NCAAF", "NCAAB", "EPL", "MLS",
)

# Words that keep their casing when a team identifier is humanised.
_UPPERCASE_TOKENS = frozenset({"fc", "sc", "afc", "cfc", "usa", "la", "ny", "sf"})

# Values a feed uses to mean "no idea".
_PLACEHOLDER_VALUES = frozenset(
    {"", "unknown", "n/a", "na", "none", "null", "tbd", "-", "--"}
)


def is_placeholder(value: object) -> bool:
    """Whether a field carries no real information."""

    return str(value or "").strip().lower() in _PLACEHOLDER_VALUES


def display_team_name(value: object) -> str:
    """Turn a feed's team identifier into something a person would write.

    CLEVELAND_GUARDIANS_MLB becomes Cleveland Guardians. The league suffix is
    dropped because the card already says which sport it is, and repeating it
    inside the team name is how MLB ends up printed twice on one line.

    An unrecognisable value returns empty rather than a cleaned-up version of
    the noise, so the caller can tell "no name" from "a name".
    """

    text = str(value or "").strip()
    if is_placeholder(text):
        return ""
    # Identifiers arrive underscored and shouting; real names arrive already
    # readable and must survive untouched.
    if "_" not in text and not text.isupper():
        return text

    parts = [part for part in re.split(r"[_\s]+", text) if part]
    while parts and parts[-1].upper() in _LEAGUE_SUFFIXES:
        parts.pop()
    if not parts:
        return ""
    words = []
    for part in parts:
        lowered = part.lower()
        words.append(part.upper() if lowered in _UPPERCASE_TOKENS else lowered.capitalize())
    return " ".join(words)


def display_matchup(value: object, *, home: object = "", away: object = "") -> str:
    """A readable "Away @ Home", preferring the teams over a raw matchup string."""

    away_name = display_team_name(away)
    home_name = display_team_name(home)
    if away_name and home_name:
        return f"{away_name} @ {home_name}"

    text = str(value or "").strip()
    if is_placeholder(text):
        return ""
    for separator in (" @ ", " vs ", " VS ", " v "):
        if separator in text:
            left, _, right = text.partition(separator)
            left_name = display_team_name(left)
            right_name = display_team_name(right)
            if left_name and right_name:
                return f"{left_name} @ {right_name}"
            return text
    return display_team_name(text) or text


def markets_for_sport(sport: object) -> frozenset[str]:
    """Market keys a sport actually has, empty when the sport is unconfigured."""

    key = _SPORT_KEYS.get(str(sport or "").strip().upper())
    if key is None:
        return frozenset()
    return frozenset(SPORT_MARKETS.get(key, ()))


def market_belongs_to_sport(sport: object, market_key: object) -> bool:
    """Whether this market exists in this sport.

    Baseball has no points. A feed that labels a batter's prop `player_points`
    has mapped a basketball stat onto a baseball event, and the resulting card
    describes a market that does not exist. Sports with no configured market
    list are not judged, so a new sport is never rejected for being new.
    """

    known = markets_for_sport(sport)
    if not known:
        return True
    return str(market_key or "").strip().lower() in known


@dataclass(frozen=True)
class Verification:
    """Whether a prop may be shown, and whether it may be selected."""

    displayable: bool
    selectable: bool
    reasons: tuple[str, ...] = field(default=())

    @property
    def status(self) -> str:
        if not self.displayable:
            return "quarantined"
        return "verified" if self.selectable else "unverified"


# Faults that make a prop meaningless rather than merely incomplete. These are
# not shown at all: there is nothing a person could do with a prop whose market
# does not exist in its sport.
_QUARANTINE_REASONS = frozenset(
    {"market_not_in_sport", "market_missing", "player_missing", "line_missing"}
)


def verify_prop(prop: object) -> Verification:
    """Judge one prop against what it claims to be.

    Returns every reason found rather than the first, because a prop with an
    unknown source and no projection has two different problems and fixing one
    does not fix the other.
    """

    reasons: list[str] = []

    player = str(getattr(prop, "player", "") or "").strip()
    if is_placeholder(player):
        reasons.append("player_missing")

    sport = getattr(prop, "sport", "")
    market_key = str(getattr(prop, "marketKey", "") or "").strip()
    market_label = str(getattr(prop, "market", "") or "").strip()
    if is_placeholder(market_key) and is_placeholder(market_label):
        reasons.append("market_missing")
    elif market_key and not market_belongs_to_sport(sport, market_key):
        reasons.append("market_not_in_sport")

    line = getattr(prop, "line", None)
    if line is None:
        reasons.append("line_missing")

    if is_placeholder(getattr(prop, "sportsbook", "")):
        reasons.append("source_unverified")

    if getattr(prop, "projection", None) is None:
        reasons.append("projection_missing")

    matchup = getattr(prop, "matchup", "")
    if is_placeholder(matchup):
        reasons.append("event_unnamed")

    quarantined = any(reason in _QUARANTINE_REASONS for reason in reasons)
    return Verification(
        displayable=not quarantined,
        selectable=not reasons,
        reasons=tuple(reasons),
    )


# What each reason means, for a card that has to explain itself.
REASON_LABELS: Mapping[str, str] = {
    "player_missing": "Player could not be identified",
    "market_missing": "Market not provided by the source",
    "market_not_in_sport": "Market does not exist in this sport",
    "line_missing": "No line published",
    "source_unverified": "Prop source could not be verified",
    "projection_missing": "No model projection available",
    "event_unnamed": "Event could not be identified",
}


def describe(reasons: Iterable[str]) -> list[str]:
    return [REASON_LABELS.get(reason, reason.replace("_", " ")) for reason in reasons]
