"""Score pregame context completeness without pretending missing data is neutral."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ContextQuality:
    score: float
    present: tuple[str, ...]
    missing: tuple[str, ...]


def evaluate_context_quality(prop: object) -> ContextQuality:
    sport = str(getattr(prop, "sport", "")).upper()
    age = getattr(prop, "dataAgeSeconds", None)
    checks: list[tuple[str, bool, float]] = [
        ("injury", str(getattr(prop, "injuryStatus", "unknown")).lower() != "unknown", .14),
        ("lineup", str(getattr(prop, "lineupStatus", "unknown")).lower() != "unknown", .14),
        ("opportunity", getattr(prop, "projectedOpportunity", None) is not None, .16),
        ("rest", getattr(prop, "restDays", None) is not None, .08),
        ("travel", getattr(prop, "travelMiles", None) is not None, .06),
        ("home_away", getattr(prop, "isHome", None) is not None, .05),
        ("live_feed_fresh", not bool(getattr(prop, "dataStale", False)) and (age is None or age <= 900), .07),
    ]
    if sport in {"NBA", "WNBA"}:
        checks.extend([
            ("opponent_allowance", getattr(prop, "opponentAllowanceByPosition", None) is not None, .10),
            ("pace", getattr(prop, "paceMultiplier", None) is not None, .08),
            ("direct_matchup", getattr(prop, "directMatchupSampleSize", 0) > 0, .04),
            ("defensive_scheme", bool(getattr(prop, "defensiveScheme", "")), .08),
        ])
    elif sport == "MLB":
        checks.extend([
            ("projected_lineup", getattr(prop, "mlbProjectedLineupMatchup", None) is not None, .12),
            ("lineup_matchup", getattr(prop, "directMatchupSampleSize", 0) > 0, .06),
        ])
    total = sum(weight for _, _, weight in checks) or 1.0
    present = tuple(name for name, available, _ in checks if available)
    missing = tuple(name for name, available, _ in checks if not available)
    earned = sum(weight for _, available, weight in checks if available)
    return ContextQuality(round(earned / total, 4), present, missing)
