"""Unified sport-aware pregame participation readiness."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable

from services.player_role_service import build_player_role

SUPPORTED_SPORTS = frozenset({"WNBA", "NBA", "MLB", "NFL", "NHL", "SOCCER", "MLS"})
SPORT_PRIORITY = {"WNBA": 1, "NBA": 1, "MLB": 2, "NFL": 3, "NHL": 4, "SOCCER": 4, "MLS": 4}
_UNAVAILABLE = frozenset({"out", "inactive", "suspended", "ruled out"})
_UNRESOLVED = frozenset({"questionable", "doubtful", "day-to-day", "day_to_day", "probable", "injury reported"})


def _text(value: object) -> str:
    return str(value or "").strip()


def _upper(value: object) -> str:
    return _text(value).upper().replace("-", "_").replace(" ", "_")


def _payload(row: dict[str, object]) -> dict[str, object]:
    value = row.get("payload")
    return value if isinstance(value, dict) else {}


def _observed_at(row: dict[str, object]) -> datetime | None:
    value = row.get("observedAt") or row.get("observed_at")
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        parsed = datetime.fromisoformat(_text(value).replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _factor(key: str, label: str, status: str, detail: str, *, required: bool = True, source: str = "") -> dict[str, object]:
    return {"key": key, "label": label, "status": status, "detail": detail, "required": required, "source": source}


def _matching(rows: Iterable[dict[str, object]], *entity_types: str) -> list[dict[str, object]]:
    wanted = {_upper(value) for value in entity_types}
    return [row for row in rows if _upper(row.get("entityType") or row.get("entity_type")) in wanted]


def _latest(rows: Iterable[dict[str, object]]) -> dict[str, object] | None:
    values = list(rows)
    if not values:
        return None
    floor = datetime.min.replace(tzinfo=timezone.utc)
    return max(values, key=lambda row: (_observed_at(row) or floor, bool(row.get("confirmed"))))


def _source(row: dict[str, object] | None) -> str:
    return _text((row or {}).get("provider"))


def _lineup_role(rows: list[dict[str, object]]) -> tuple[str, dict[str, object] | None]:
    lineup = _latest(_matching(rows, "LINEUP", "TEAM_SHEET", "ACTIVE_LIST", "DEPTH_CHART"))
    if lineup is None:
        return "UNKNOWN", None
    status = _upper(lineup.get("status"))
    payload = _payload(lineup)
    role = _upper(payload.get("role") or payload.get("lineupRole") or payload.get("positionRole"))
    combined = "_".join(filter(None, (status, role)))
    confirmed = bool(lineup.get("confirmed"))
    if any(token in combined for token in ("INACTIVE", "SCRATCH", "OUT")):
        return "INACTIVE", lineup
    if any(token in combined for token in ("SUBSTITUTE", "BENCH")):
        return ("CONFIRMED_BENCH" if confirmed else "PROJECTED_BENCH"), lineup
    if any(token in combined for token in ("STARTER", "STARTING_XI", "STARTING_GOALIE")):
        return ("CONFIRMED_STARTER" if confirmed else "PROJECTED_STARTER"), lineup
    if any(token in combined for token in ("ACTIVE", "AVAILABLE")):
        return ("CONFIRMED_ACTIVE" if confirmed else "PROJECTED_ACTIVE"), lineup
    return ("CONFIRMED_ROLE" if confirmed else "PROJECTED_ROLE"), lineup


def _restriction(rows: list[dict[str, object]], prop: object) -> tuple[str, str, str]:
    latest = _latest(rows)
    ordered = sorted(rows, key=lambda item: _observed_at(item) or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
    for row in ordered:
        payload = _payload(row)
        status = _upper(row.get("status"))
        raw = payload.get("minutesRestriction", payload.get("snapRestriction", payload.get("roleRestriction")))
        restricted = raw is True or (raw not in (None, False, "", 0) and _upper(raw) not in {"FALSE", "NONE", "NO"})
        if restricted or "RESTRICTION" in status or "LIMIT" in status:
            return "RESTRICTED", _text(raw) or _text(row.get("status")) or "A workload restriction was reported.", _source(row)
    role_change = _upper(getattr(prop, "roleChange", ""))
    if any(token in role_change for token in ("RESTRICTION", "LIMITED")):
        return "RESTRICTED", role_change.replace("_", " ").title(), "model context"
    return "CLEAR" if latest else "UNKNOWN", "No workload restriction reported." if latest else "No verified workload-status feed.", _source(latest)


def _availability_factor(prop: object) -> tuple[dict[str, object], bool, bool]:
    injury = _text(getattr(prop, "injuryStatus", "unknown")).lower()
    if injury in _UNAVAILABLE:
        return _factor("availability", "Player availability", "UNAVAILABLE", f"Player is listed {injury}."), False, True
    if injury in _UNRESOLVED:
        return _factor("availability", "Player availability", "UNSETTLED", f"Player is listed {injury}."), False, False
    if injury in {"healthy", "active", "available", "no injury reported"}:
        return _factor("availability", "Player availability", "CONFIRMED", "No current unavailability is reported."), True, False
    return _factor("availability", "Player availability", "MISSING", "Current availability has not been verified."), False, False


def _basketball(prop: object, rows: list[dict[str, object]]) -> list[dict[str, object]]:
    role, lineup = _lineup_role(rows)
    confirmed = role in {"CONFIRMED_STARTER", "CONFIRMED_BENCH", "CONFIRMED_ROLE", "CONFIRMED_ACTIVE"}
    factors = [_factor("rotation_role", "Confirmed rotation role", "CONFIRMED" if confirmed else "UNSETTLED" if role.startswith("PROJECTED") else "MISSING", role.replace("_", " ").title() if lineup else "Starter or bench role has not been confirmed.", source=_source(lineup))]
    restriction, detail, source = _restriction(rows, prop)
    factors.append(_factor("minutes_restriction", "Minutes restriction", restriction, detail, required=restriction == "RESTRICTED", source=source))
    return factors


def _is_pitcher_prop(prop: object, rows: list[dict[str, object]]) -> bool:
    market = " ".join(_text(getattr(prop, key, "")) for key in ("market", "marketKey", "category")).lower()
    if any(token in market for token in ("strikeout", "pitcher", "earned run", "outs recorded", "pitch count", "hits allowed")):
        return True
    return any("PITCHER" in _upper(_payload(row).get("role")) for row in rows)


def _mlb(prop: object, rows: list[dict[str, object]], event_rows: list[dict[str, object]]) -> list[dict[str, object]]:
    latest = _latest(_matching(rows, "LINEUP"))
    payload = _payload(latest or {})
    status = _upper((latest or {}).get("status"))
    confirmed = bool((latest or {}).get("confirmed"))
    pitcher = _is_pitcher_prop(prop, rows)
    if pitcher:
        role = _upper(payload.get("role"))
        starter = confirmed and ("START" in status or "STARTING_PITCHER" in role)
        factors = [_factor("starting_pitcher", "Confirmed starting pitcher", "CONFIRMED" if starter else "UNSETTLED" if latest else "MISSING", "Starting pitcher is confirmed." if starter else "Probable pitcher is not yet an official starter.", source=_source(latest))]
    else:
        order = payload.get("battingOrder")
        starter = confirmed and "START" in status and order not in (None, "", 0, "0")
        factors = [_factor("batting_order", "Confirmed batting order", "CONFIRMED" if starter else "UNSETTLED" if latest else "MISSING", f"Batting order position {order} is confirmed." if starter else "Official batting order is not confirmed.", source=_source(latest))]
    combined = event_rows + rows
    opener = next((row for row in combined if _payload(row).get("opener") is True or "BULLPEN" in _upper(row.get("status")) or "OPENER" in _upper(row.get("status"))), None)
    scratch = next((row for row in rows if "SCRATCH" in _upper(row.get("status"))), None)
    factors.append(_factor("scratch_status", "Scratch status", "BLOCKED" if scratch else "CLEAR", "Player has been scratched." if scratch else "No player scratch is reported.", required=bool(scratch), source=_source(scratch)))
    factors.append(_factor("pitching_plan", "Opener or bullpen plan", "WARNING" if opener else "CLEAR", "An opener or bullpen game is reported." if opener else "No opener or bullpen-game flag is reported.", required=bool(opener and pitcher), source=_source(opener)))
    return factors


def _nfl(prop: object, rows: list[dict[str, object]]) -> list[dict[str, object]]:
    role, lineup = _lineup_role(rows)
    active = role in {"CONFIRMED_ACTIVE", "CONFIRMED_STARTER", "CONFIRMED_ROLE"}
    market = " ".join(_text(getattr(prop, key, "")) for key in ("market", "marketKey", "category")).lower()
    quarterback = any(token in market for token in ("passing", "quarterback", "qb ")) or "QB" == _upper(_payload(lineup or {}).get("position"))
    factors = [_factor("active_status", "Official active/inactive status", "CONFIRMED" if active else "BLOCKED" if role == "INACTIVE" else "UNSETTLED" if lineup else "MISSING", role.replace("_", " ").title() if lineup else "Game-day active status has not been verified.", source=_source(lineup))]
    if quarterback:
        factors.append(_factor("starting_quarterback", "Confirmed starting quarterback", "CONFIRMED" if role == "CONFIRMED_STARTER" else "UNSETTLED", "Quarterback starter is confirmed." if role == "CONFIRMED_STARTER" else "Starting quarterback has not been confirmed.", source=_source(lineup)))
    depth = _latest(_matching(rows, "DEPTH_CHART"))
    factors.append(_factor("depth_chart", "Depth-chart role", "CONFIRMED" if depth and depth.get("confirmed") else "MISSING", _text((depth or {}).get("status")) or "No verified depth-chart update.", required=False, source=_source(depth)))
    restriction, detail, source = _restriction(rows, prop)
    factors.append(_factor("snap_restriction", "Snap restriction", restriction, detail, required=restriction == "RESTRICTED", source=source))
    return factors


def _nhl(prop: object, rows: list[dict[str, object]]) -> list[dict[str, object]]:
    role, lineup = _lineup_role(rows)
    market = " ".join(_text(getattr(prop, key, "")) for key in ("market", "marketKey", "category")).lower()
    goalie = any(token in market for token in ("goalie", "saves", "goals allowed")) or "GOALIE" in _upper(_payload(lineup or {}).get("position"))
    confirmed = role == "CONFIRMED_STARTER" if goalie else role in {"CONFIRMED_STARTER", "CONFIRMED_ACTIVE", "CONFIRMED_ROLE"}
    factors = [_factor("starting_goalie" if goalie else "skater_status", "Confirmed starting goalie" if goalie else "Active/scratch status", "CONFIRMED" if confirmed else "BLOCKED" if role == "INACTIVE" else "UNSETTLED" if lineup else "MISSING", role.replace("_", " ").title() if lineup else "Official game role has not been verified.", source=_source(lineup))]
    line = _latest(_matching(rows, "LINE_COMBINATION", "DEPTH_CHART"))
    factors.append(_factor("line_combination", "Line combination", "CONFIRMED" if line and line.get("confirmed") else "MISSING", _text((line or {}).get("status")) or "Current line combination is not verified.", required=not goalie, source=_source(line)))
    return factors


def _soccer(rows: list[dict[str, object]], event_rows: list[dict[str, object]]) -> list[dict[str, object]]:
    role, lineup = _lineup_role(rows)
    team_sheet = role in {"CONFIRMED_STARTER", "CONFIRMED_BENCH"}
    factors = [_factor("official_team_sheet", "Official starting XI/substitutes", "CONFIRMED" if team_sheet else "UNSETTLED" if lineup else "MISSING", role.replace("_", " ").title() if lineup else "Official team sheet has not been published.", source=_source(lineup))]
    formation = next((row for row in event_rows + rows if _payload(row).get("formation")), None)
    factors.append(_factor("formation", "Confirmed formation", "CONFIRMED" if formation and formation.get("confirmed") else "MISSING", f"Formation {_payload(formation or {}).get('formation')} is confirmed." if formation else "Official formation is not available.", source=_source(formation)))
    return factors


def assess_pregame_availability(prop: object, *, observations: Iterable[dict[str, object]] = (), event_observations: Iterable[dict[str, object]] = ()) -> dict[str, object]:
    sport = _upper(getattr(prop, "sport", ""))
    if sport not in SUPPORTED_SPORTS:
        return {}
    normalized_sport = "SOCCER" if sport == "MLS" else sport
    rows, event_rows = list(observations), list(event_observations)
    availability, available, unavailable = _availability_factor(prop)
    if normalized_sport in {"WNBA", "NBA"}:
        factors, recheck = _basketball(prop, rows), "After starters, bench roles and workload restrictions are confirmed"
    elif normalized_sport == "MLB":
        factors, recheck = _mlb(prop, rows, event_rows), "After the official batting order and starting pitcher are confirmed"
    elif normalized_sport == "NFL":
        factors, recheck = _nfl(prop, rows), "After game-day actives, starters and snap roles are confirmed"
    elif normalized_sport == "NHL":
        factors, recheck = _nhl(prop, rows), "After the starting goalie, scratches and lines are confirmed"
    else:
        factors, recheck = _soccer(rows, event_rows), "After the official XI, formation and substitutes are published"
    # An official player role is itself proof of participation even when a
    # separate injury feed has no row for the player. It is not a claim of
    # perfect health; it only avoids calling a published starter/sub inactive.
    if availability["status"] == "MISSING" and any(
        factor["required"] and factor["status"] == "CONFIRMED"
        for factor in factors
    ):
        availability = _factor(
            "availability", "Player availability", "CONFIRMED",
            "Official game-role data confirms the player is participating.",
            source=next((str(factor["source"]) for factor in factors if factor["status"] == "CONFIRMED"), ""),
        )
        available = True
    factors.insert(0, availability)
    blocking = [factor for factor in factors if factor["required"] and factor["status"] not in {"CONFIRMED", "CLEAR"}]
    confirmed = sum(factor["status"] in {"CONFIRMED", "CLEAR"} for factor in factors)
    score = round(100 * confirmed / max(1, len(factors)))
    if unavailable or any(factor["status"] == "BLOCKED" for factor in factors):
        status, ready, score = "UNAVAILABLE", False, 0
    elif blocking or not available:
        status, ready = "WAIT", False
    else:
        status, ready = "READY", True
    warnings = [str(factor["detail"]) for factor in factors if factor["status"] not in {"CONFIRMED", "CLEAR"}]
    observed = [_observed_at(row) for row in rows + event_rows]
    latest = max((value for value in observed if value is not None), default=None)
    sources = sorted({_source(row) for row in rows + event_rows if _source(row)})
    return {"sport": normalized_sport, "priority": SPORT_PRIORITY[sport], "status": status, "ready": ready, "score": score, "factors": factors, "warnings": warnings, "recheck": "" if ready else recheck, "sources": sources, "lastVerifiedAt": latest.isoformat() if latest else None, "playerRole": build_player_role(prop, observations=rows)}


def apply_pregame_availability(prop: object, *, observations: Iterable[dict[str, object]] = (), event_observations: Iterable[dict[str, object]] = ()) -> None:
    assessment = assess_pregame_availability(prop, observations=observations, event_observations=event_observations)
    if assessment:
        prop.pregameAvailability = assessment
        prop.playerRole = assessment.get("playerRole", {})
