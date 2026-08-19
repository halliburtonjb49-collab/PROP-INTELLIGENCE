"""Normalize sport-specific opportunity evidence into one player-role object."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable


def _text(value: object) -> str:
    return str(value or "").strip()


def _upper(value: object) -> str:
    return _text(value).upper().replace("-", "_").replace(" ", "_")


def _number(value: object) -> float | None:
    try:
        return float(value) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


def _ratio(value: object) -> float | None:
    parsed = _number(value)
    if parsed is None:
        return None
    if parsed > 1:
        parsed /= 100
    return max(0.0, min(1.0, parsed))


def _observed_at(row: dict[str, object]) -> datetime | None:
    value = row.get("observedAt") or row.get("observed_at")
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        parsed = datetime.fromisoformat(_text(value).replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _payload(row: dict[str, object]) -> dict[str, object]:
    value = row.get("payload")
    return value if isinstance(value, dict) else {}


def _first(payload: dict[str, object], *keys: str) -> object:
    for key in keys:
        if payload.get(key) not in (None, ""):
            return payload[key]
    return None


def _depth_score(rank: int | None) -> float | None:
    if rank is None:
        return None
    return {1: 1.0, 2: 0.72, 3: 0.42, 4: 0.2}.get(rank, 0.1)


def _line_score(line: int | None) -> float | None:
    if line is None:
        return None
    return {1: 1.0, 2: 0.8, 3: 0.55, 4: 0.3}.get(line, 0.15)


def _pp_score(unit: int | None) -> float | None:
    if unit is None:
        return None
    return {1: 1.0, 2: 0.65}.get(unit, 0.2)


def _weighted_score(values: Iterable[tuple[float, float | None]]) -> int:
    weighted = [(weight, value) for weight, value in values if value is not None]
    if not weighted:
        return 0
    # Missing role inputs reduce certainty instead of being silently replaced
    # with league-average assumptions.
    return round(100 * sum(weight * value for weight, value in weighted))


def build_player_role(
    prop: object,
    *,
    observations: Iterable[dict[str, object]] = (),
) -> dict[str, object]:
    rows = sorted(
        list(observations),
        key=lambda row: _observed_at(row) or datetime.min.replace(tzinfo=timezone.utc),
    )
    payload: dict[str, object] = {}
    for row in rows:
        payload.update(_payload(row))

    latest = rows[-1] if rows else {}
    status_text = "_".join(_upper(row.get("status")) for row in rows)
    confirmed = any(bool(row.get("confirmed")) for row in rows)
    inactive = any(token in status_text for token in ("INACTIVE", "SCRATCH", "OUT"))
    starter = any("START" in _upper(row.get("status")) for row in rows)
    projected = any("PROJECTED" in _upper(row.get("status")) for row in rows)
    injury = _text(getattr(prop, "injuryStatus", "unknown")).lower()
    sport = _upper(getattr(prop, "sport", ""))

    depth_rank_raw = _number(_first(payload, "roleRank", "depthRank", "posRank", "pos_rank"))
    depth_rank = int(depth_rank_raw) if depth_rank_raw is not None else None
    line_raw = _number(_first(payload, "lineNumber", "line", "line_number"))
    line_number = int(line_raw) if line_raw is not None else None
    pp_raw = _number(_first(payload, "powerPlayUnit", "ppUnit", "power_play_unit"))
    power_play_unit = int(pp_raw) if pp_raw is not None else None
    batting_raw = _number(_first(payload, "battingOrder", "batting_order"))
    batting_order = int(batting_raw) if batting_raw is not None else None

    expected_minutes = _number(_first(payload, "expectedMinutes", "projectedMinutes"))
    expected_snaps = _number(_first(payload, "expectedSnaps", "projectedSnaps"))
    expected_toi = _number(_first(payload, "expectedToi", "expectedTOI", "projectedToi"))
    snap_pct = _ratio(_first(payload, "expectedSnapPct", "snapPct", "offensePct", "offense_pct"))
    route_participation = _ratio(_first(payload, "routeParticipation", "route_participation"))
    target_share = _ratio(_first(payload, "targetShare", "target_share"))
    rush_share = _ratio(_first(payload, "rushShare", "rush_share"))
    red_zone_share = _ratio(_first(payload, "redZoneShare", "red_zone_share"))
    usage = _ratio(_first(payload, "usageProjection", "usageRate", "usage"))

    supplied_probability = _ratio(_first(payload, "starterProbability", "starter_probability"))
    if inactive or injury in {"out", "inactive", "ruled out", "suspended"}:
        starter_probability = 0.0
        state = "UNAVAILABLE"
    elif supplied_probability is not None:
        starter_probability = supplied_probability
        state = "CONFIRMED" if confirmed and starter else "PROJECTED" if starter_probability >= 0.8 else "UNCERTAIN"
    elif confirmed and starter:
        starter_probability, state = 1.0, "CONFIRMED"
    else:
        depth = _depth_score(depth_rank)
        evidence = [value for value in (depth, snap_pct, route_participation) if value is not None]
        starter_probability = sum(evidence) / len(evidence) if evidence else (0.8 if projected else 0.0)
        state = "PROJECTED" if starter_probability >= 0.8 else "UNCERTAIN"

    role = _upper(_first(payload, "role", "lineupRole", "positionRole"))
    if not role:
        role = _upper(latest.get("status")) or "UNKNOWN"
    position = _upper(_first(payload, "position", "posAbb", "pos_abb"))

    result: dict[str, object] = {
        "sport": sport,
        "playerId": _text(getattr(prop, "playerId", "") or latest.get("providerPlayerId") or latest.get("provider_player_id")),
        "player": _text(getattr(prop, "player", "") or latest.get("playerName") or latest.get("player_name")),
        "team": _text(latest.get("team")),
        "status": state,
        "starterProbability": round(100 * starter_probability),
        "role": role,
        "roleRank": depth_rank,
        "position": position,
        "expectedMinutes": expected_minutes,
        "expectedSnaps": expected_snaps,
        "expectedToi": expected_toi,
        "usageProjection": round(100 * usage, 1) if usage is not None else None,
        "lineNumber": line_number,
        "powerPlayUnit": power_play_unit,
        "battingOrder": batting_order,
        "injuryStatus": injury,
        "confirmed": state == "CONFIRMED",
        "source": _text(latest.get("provider")),
        "lastUpdated": (_observed_at(latest) or None).isoformat() if latest else None,
    }

    if sport == "NFL":
        opportunity_share = max(
            (value for value in (target_share, rush_share) if value is not None),
            default=None,
        )
        availability = 0.0 if inactive else 1.0 if confirmed else 0.65
        role_score = _weighted_score((
            (0.20, _depth_score(depth_rank)),
            (0.25, snap_pct),
            (0.20, route_participation),
            (0.15, opportunity_share),
            (0.10, red_zone_share),
            (0.10, availability),
        ))
        result["nflExpectedRole"] = {
            "expectedSnapPct": round(100 * snap_pct, 1) if snap_pct is not None else None,
            "routeParticipation": round(100 * route_participation, 1) if route_participation is not None else None,
            "targetShare": round(100 * target_share, 1) if target_share is not None else None,
            "rushShare": round(100 * rush_share, 1) if rush_share is not None else None,
            "redZoneShare": round(100 * red_zone_share, 1) if red_zone_share is not None else None,
            "roleScore": 0 if inactive else role_score,
        }
    elif sport == "NHL":
        toi_score = min(1.0, expected_toi / 24) if expected_toi is not None else None
        shot_rate = _ratio(_first(payload, "shotRate", "shot_rate"))
        team_usage = _ratio(_first(payload, "teamUsage", "team_usage"))
        opponent = _ratio(_first(payload, "opponentFactor", "opponent_factor"))
        opportunity = _weighted_score((
            (0.30, toi_score),
            (0.20, _line_score(line_number)),
            (0.20, _pp_score(power_play_unit)),
            (0.10, shot_rate),
            (0.10, team_usage),
            (0.10, opponent),
        ))
        result["nhlOpportunity"] = {
            "expectedToi": expected_toi,
            "lineNumber": line_number,
            "powerPlayUnit": power_play_unit,
            "opportunityScore": opportunity,
        }

    return result
