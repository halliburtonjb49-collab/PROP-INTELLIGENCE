"""Detect and retain meaningful player availability changes."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from threading import Lock
from typing import Iterable

from services.distributed_cache_service import get_json, set_json

_SNAPSHOT_KEY = "injury-impact-alerts:snapshot:v1"
_HISTORY_KEY = "injury-impact-alerts:history:v1"
_TTL_SECONDS = 7 * 24 * 60 * 60
_LOCK = Lock()
_LOCAL_SNAPSHOT: dict[str, dict[str, object]] | None = None
_LOCAL_HISTORY: list[dict[str, object]] = []
_RANK = {"NONE": 0, "WATCH": 1, "HIGH": 2, "CRITICAL": 3}


def _value(row: object, name: str, default: object = "") -> object:
    if isinstance(row, dict):
        return row.get(name, default)
    return getattr(row, name, default)


def _text(value: object) -> str:
    return str(value or "").strip().lower().replace("_", " ")


def _number(value: object) -> float | None:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _player_key(row: object) -> str:
    event = str(_value(row, "eventId") or _value(row, "matchup") or "").strip()
    player = str(
        _value(row, "canonicalPlayerId")
        or _value(row, "playerId")
        or _value(row, "player")
        or "unknown"
    ).strip().lower()
    return f"{event}|{player}"


def _severity(row: object) -> str:
    injury = _text(_value(row, "injuryStatus", "unknown"))
    lineup = _text(_value(row, "lineupStatus", "unknown"))
    role = _text(_value(row, "roleChange", "unknown"))
    if injury in {"out", "inactive", "injured reserve", "suspended"} or lineup in {
        "out",
        "inactive",
    }:
        return "CRITICAL"
    if injury == "doubtful" or lineup in {
        "doubtful",
        "bench",
        "limited",
        "minutes restriction",
    }:
        return "HIGH"
    if injury in {
        "questionable",
        "day to day",
        "day-to-day",
        "game time decision",
        "probable",
    }:
        return "WATCH"
    if lineup not in {
        "",
        "unknown",
        "unavailable",
        "no report",
        "not reported",
        "confirmed",
        "confirmed starter",
        "starter",
        "starting",
        "active",
    }:
        return "WATCH"
    if role in {"expanded", "reduced"}:
        return "WATCH"
    for field in ("usageMultiplier", "wowyMultiplier", "opportunityMultiplier"):
        value = _number(_value(row, field, None))
        if value is not None and abs(value - 1) >= 0.02:
            return "WATCH"
    return "NONE"


def _signature(rows: list[object], level: str) -> str:
    factors: set[tuple[object, ...]] = set()
    for row in rows:
        values: list[object] = [
            _text(_value(row, "injuryStatus", "unknown")),
            _text(_value(row, "lineupStatus", "unknown")),
            _text(_value(row, "roleChange", "unknown")),
        ]
        for field in ("usageMultiplier", "wowyMultiplier", "opportunityMultiplier"):
            value = _number(_value(row, field, None))
            values.append(round(value, 3) if value is not None else None)
        factors.add(tuple(values))
    payload = json.dumps([level, sorted(factors, key=str)], separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()[:24]


def build_injury_impact_snapshot(props: Iterable[object]) -> dict[str, dict[str, object]]:
    groups: dict[str, list[object]] = {}
    for prop in props:
        groups.setdefault(_player_key(prop), []).append(prop)
    snapshot: dict[str, dict[str, object]] = {}
    for key, rows in groups.items():
        representative = max(rows, key=lambda row: _RANK[_severity(row)])
        level = _severity(representative)
        snapshot[key] = {
            "signature": _signature(rows, level),
            "level": level,
            "player": str(_value(representative, "player") or "Unknown player"),
            "sport": str(_value(representative, "sport") or "ALL").upper(),
            "matchup": str(_value(representative, "matchup") or ""),
            "injuryStatus": _text(_value(representative, "injuryStatus", "unknown")),
            "lineupStatus": _text(_value(representative, "lineupStatus", "unknown")),
            "roleChange": _text(_value(representative, "roleChange", "unknown")),
            "markets": sorted(
                {
                    str(
                        _value(row, "displayMarket")
                        or _value(row, "market")
                        or "market"
                    ).strip()
                    for row in rows
                }
            ),
            "sites": sorted(
                {
                    str(_value(row, "sportsbook") or "").strip().upper()
                    for row in rows
                    if str(_value(row, "sportsbook") or "").strip()
                }
            ),
        }
    return snapshot


def detect_injury_impact_changes(
    previous: dict[str, dict[str, object]],
    current: dict[str, dict[str, object]],
    *,
    occurred_at: datetime | None = None,
) -> list[dict[str, object]]:
    now = (occurred_at or datetime.now(timezone.utc)).astimezone(timezone.utc)
    events: list[dict[str, object]] = []
    for key, row in current.items():
        prior = previous.get(key)
        if prior is None or prior.get("signature") == row.get("signature"):
            continue
        level = str(row.get("level") or "NONE")
        prior_level = str(prior.get("level") or "NONE")
        if level == "NONE" and prior_level == "NONE":
            continue
        cleared = level == "NONE"
        effective_level = "CLEARED" if cleared else level
        player = str(row.get("player") or "Unknown player")
        markets = [str(value) for value in (row.get("markets") or [])]
        market_text = ", ".join(markets[:3]) or "active props"
        if cleared:
            title = "INJURY IMPACT CLEARED"
            message = f"{player} no longer has a verified availability or role-impact warning."
        else:
            title = "AVAILABILITY BLOCK" if level == "CRITICAL" else "INJURY IMPACT CHANGED"
            injury = str(row.get("injuryStatus") or "unknown")
            lineup = str(row.get("lineupStatus") or "unknown")
            role = str(row.get("roleChange") or "unknown")
            if injury not in {"", "unknown", "no injury reported", "active", "healthy"}:
                status = f"injury status {injury}"
            elif lineup not in {"", "unknown", "confirmed", "active", "starter"}:
                status = f"lineup status {lineup}"
            elif role not in {"", "unknown", "stable"}:
                status = f"role trend {role}"
            else:
                status = "verified model context changed"
            message = f"{player}: {status}. Recheck {market_text} before acting."
        event_id = hashlib.sha256(
            f"{key}|{row.get('signature')}|{effective_level}".encode()
        ).hexdigest()[:24]
        events.append(
            {
                "eventId": event_id,
                "type": "injury.impact.changed",
                "level": effective_level,
                "title": title,
                "message": message,
                "player": player,
                "sport": row.get("sport") or "ALL",
                "matchup": row.get("matchup") or "",
                "injuryStatus": row.get("injuryStatus") or "unknown",
                "lineupStatus": row.get("lineupStatus") or "unknown",
                "roleChange": row.get("roleChange") or "unknown",
                "markets": markets,
                "sites": row.get("sites") or [],
                "occurredAt": now.isoformat().replace("+00:00", "Z"),
            }
        )
    events.sort(key=lambda event: -_RANK.get(str(event["level"]), 0))
    return events


def evaluate_injury_impact_changes(props: Iterable[object]) -> list[dict[str, object]]:
    global _LOCAL_SNAPSHOT, _LOCAL_HISTORY
    current = build_injury_impact_snapshot(props)
    with _LOCK:
        shared = get_json(_SNAPSHOT_KEY)
        previous = shared if isinstance(shared, dict) else _LOCAL_SNAPSHOT
        events = [] if previous is None else detect_injury_impact_changes(previous, current)
        _LOCAL_SNAPSHOT = current
        set_json(_SNAPSHOT_KEY, current, ttl_seconds=_TTL_SECONDS)
        if events:
            shared_history = get_json(_HISTORY_KEY)
            history = shared_history if isinstance(shared_history, list) else _LOCAL_HISTORY
            _LOCAL_HISTORY = (events + list(history))[:100]
            set_json(_HISTORY_KEY, _LOCAL_HISTORY, ttl_seconds=_TTL_SECONDS)
        return events


def injury_alert_history(limit: int = 50) -> list[dict[str, object]]:
    shared = get_json(_HISTORY_KEY)
    history = shared if isinstance(shared, list) else _LOCAL_HISTORY
    return [
        dict(row)
        for row in history[: max(1, min(limit, 100))]
        if isinstance(row, dict)
    ]


def reset_injury_alert_state_for_tests() -> None:
    global _LOCAL_SNAPSHOT, _LOCAL_HISTORY
    with _LOCK:
        _LOCAL_SNAPSHOT = None
        _LOCAL_HISTORY = []
