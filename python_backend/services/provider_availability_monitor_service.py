"""Persist and classify official pregame provider availability by sport."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Iterable

from services.distributed_cache_service import get_json, set_json

_CACHE_KEY = "operations:provider-availability:v1"
_CACHE_TTL_SECONDS = 172_800
_REFRESH_MINUTES = 10
_STALE_MINUTES = 25
_LOCAL_LOCK = Lock()
_LOCAL_SNAPSHOT: dict[str, object] | None = None

_SPORTS = (
    ("WNBA", "Sportradar WNBA"),
    ("NBA", "Sportradar NBA"),
    ("MLB", "MLB Stats API / SportsDataIO"),
    ("NFL", "Sportradar NFL"),
    ("NHL", "Sportradar NHL"),
    ("SOCCER", "Sportradar Soccer"),
)


def _utc(value: datetime | None = None) -> datetime:
    current = value or datetime.now(timezone.utc)
    return current if current.tzinfo else current.replace(tzinfo=timezone.utc)


def _sport_for(provider: str) -> str | None:
    value = provider.lower()
    if "wnba" in value:
        return "WNBA"
    if "nba" in value:
        return "NBA"
    if "mlb" in value:
        return "MLB"
    if "nfl" in value:
        return "NFL"
    if "nhl" in value:
        return "NHL"
    if "soccer" in value:
        return "SOCCER"
    return None


def _authorization(row: dict[str, object]) -> str:
    skipped = str(row.get("skipped") or "").lower()
    if "not entitled" in skipped:
        return "NOT_ENTITLED"
    if "not configured" in skipped:
        return "NOT_CONFIGURED"
    if row.get("error"):
        return "ERROR"
    return "AUTHORIZED"


def record_provider_availability(
    results: Iterable[dict[str, object]], *, observed_at: datetime | None = None,
) -> dict[str, object]:
    """Store one normalized snapshot after every pregame sync."""

    global _LOCAL_SNAPSHOT
    now = _utc(observed_at)
    grouped: dict[str, list[dict[str, object]]] = {
        sport: [] for sport, _ in _SPORTS
    }
    for raw in results:
        row = dict(raw)
        sport = _sport_for(str(row.get("provider") or ""))
        if sport in grouped:
            grouped[sport].append(row)

    sports: list[dict[str, object]] = []
    alerts: list[dict[str, object]] = []
    for sport, provider_label in _SPORTS:
        rows = grouped[sport]
        authorizations = [_authorization(row) for row in rows]
        authorized = any(value == "AUTHORIZED" for value in authorizations)
        if authorized:
            authorization = "AUTHORIZED"
        elif "NOT_ENTITLED" in authorizations:
            authorization = "NOT_ENTITLED"
        elif "NOT_CONFIGURED" in authorizations or not rows:
            authorization = "NOT_CONFIGURED"
        else:
            authorization = "ERROR"

        games_checked = sum(
            int(row.get("attempted") or row.get("gamesChecked") or 0)
            for row in rows
        )
        scheduled_games = sum(
            int(row.get("games") or row.get("events") or 0) for row in rows
        )
        observations = sum(int(row.get("observations") or 0) for row in rows)
        created = sum(int(row.get("created") or 0) for row in rows)
        confirmed_players = sum(
            int(row.get("confirmedPlayers") or row.get("confirmed") or 0)
            for row in rows
        )
        confirmed_starters = sum(
            int(row.get("confirmedStarters") or 0) for row in rows
        )
        failed_events = sum(int(row.get("failedEvents") or 0) for row in rows)
        errors = [str(row["error"]) for row in rows if row.get("error")]
        missing: list[str] = []
        if authorization == "NOT_ENTITLED":
            missing.append("Provider plan does not include this sport.")
        elif authorization == "NOT_CONFIGURED":
            missing.append("Provider credentials are not configured.")
        elif authorization == "ERROR":
            missing.append("The latest provider request failed.")
        if games_checked > 0 and confirmed_players == 0:
            missing.append("Games are in the lineup window but no players are confirmed.")
        if failed_events:
            missing.append(
                f"{failed_events} game-level availability request(s) failed; retry scheduled."
            )
        if errors:
            missing.extend(errors[:2])

        if authorization in {"NOT_ENTITLED", "NOT_CONFIGURED", "ERROR"}:
            status = "NOT_ENTITLED" if authorization == "NOT_ENTITLED" else "UNAVAILABLE"
        elif missing:
            status = "PARTIAL"
        else:
            status = "HEALTHY"
        detail = (
            "No games are currently inside the confirmation window."
            if authorized and games_checked == 0
            else "Latest provider check completed."
        )
        item = {
            "sport": sport,
            "provider": provider_label,
            "status": status,
            "authorizationStatus": authorization,
            "lastSuccessfulSync": now.isoformat() if authorized else None,
            "lastAttemptAt": now.isoformat(),
            "nextRefreshAt": (now + timedelta(minutes=_REFRESH_MINUTES)).isoformat(),
            "scheduledGames": scheduled_games,
            "gamesChecked": games_checked,
            "playersConfirmed": confirmed_players,
            "startersConfirmed": confirmed_starters,
            "failedEvents": failed_events,
            "observationsFound": observations,
            "observationsCreated": created,
            "missingData": missing,
            "stale": False,
            "detail": detail,
            "providers": [
                {
                    "name": str(row.get("provider") or "unknown"),
                    "authorizationStatus": _authorization(row),
                    "error": row.get("error"),
                    "skipped": row.get("skipped"),
                }
                for row in rows
            ],
        }
        sports.append(item)
        if status != "HEALTHY":
            alerts.append({
                "sport": sport,
                "status": status,
                "message": missing[0] if missing else "Availability needs review.",
            })

    snapshot: dict[str, object] = {
        "generatedAt": now.isoformat(),
        "refreshIntervalMinutes": _REFRESH_MINUTES,
        "staleAfterMinutes": _STALE_MINUTES,
        "overallStatus": "HEALTHY" if not alerts else "ATTENTION",
        "sports": sports,
        "alerts": alerts,
    }
    with _LOCAL_LOCK:
        _LOCAL_SNAPSHOT = snapshot
    set_json(_CACHE_KEY, snapshot, ttl_seconds=_CACHE_TTL_SECONDS)
    return snapshot


def provider_availability_snapshot(
    *, now: datetime | None = None,
) -> dict[str, object]:
    """Return the latest snapshot with freshness recalculated at read time."""

    current = _utc(now)
    shared = get_json(_CACHE_KEY)
    with _LOCAL_LOCK:
        payload = shared if isinstance(shared, dict) else _LOCAL_SNAPSHOT
    if not isinstance(payload, dict):
        return {
            "generatedAt": None,
            "refreshIntervalMinutes": _REFRESH_MINUTES,
            "staleAfterMinutes": _STALE_MINUTES,
            "overallStatus": "UNAVAILABLE",
            "sports": [
                {
                    "sport": sport,
                    "provider": provider,
                    "status": "UNAVAILABLE",
                    "authorizationStatus": "UNKNOWN",
                    "lastSuccessfulSync": None,
                    "nextRefreshAt": None,
                    "scheduledGames": 0,
                    "gamesChecked": 0,
                    "playersConfirmed": 0,
                    "startersConfirmed": 0,
                    "observationsFound": 0,
                    "observationsCreated": 0,
                    "missingData": ["No availability sync has been recorded yet."],
                    "stale": True,
                }
                for sport, provider in _SPORTS
            ],
            "alerts": [{"status": "UNAVAILABLE", "message": "No availability sync has been recorded yet."}],
        }

    result = dict(payload)
    sports: list[dict[str, object]] = []
    alerts: list[dict[str, object]] = []
    for raw in payload.get("sports", []):
        if not isinstance(raw, dict):
            continue
        item = dict(raw)
        last_attempt = item.get("lastAttemptAt")
        try:
            observed = datetime.fromisoformat(str(last_attempt).replace("Z", "+00:00"))
            stale = current - observed > timedelta(minutes=_STALE_MINUTES)
        except (TypeError, ValueError):
            stale = True
        item["stale"] = stale
        if stale:
            item["status"] = "UNAVAILABLE"
            missing = list(item.get("missingData") or [])
            if "Latest availability data is stale." not in missing:
                missing.append("Latest availability data is stale.")
            item["missingData"] = missing
        sports.append(item)
        if item.get("status") != "HEALTHY":
            alerts.append({
                "sport": item.get("sport"),
                "status": item.get("status"),
                "message": (item.get("missingData") or ["Availability needs review."])[0],
            })
    result["sports"] = sports
    result["alerts"] = alerts
    result["overallStatus"] = "HEALTHY" if not alerts else "ATTENTION"
    result["checkedAt"] = current.isoformat()
    return result
