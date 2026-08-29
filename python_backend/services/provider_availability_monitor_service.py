"""Persist and classify official pregame provider availability by sport."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Iterable

from database.postgres import database_is_configured, get_database_pool
from services.distributed_cache_service import get_json, set_json

_CACHE_KEY = "operations:provider-availability:v1"
_CACHE_TTL_SECONDS = 172_800
_REFRESH_MINUTES = 10
_STALE_MINUTES = 25
_LOCAL_LOCK = Lock()
_LOCAL_SNAPSHOT: dict[str, object] | None = None
LOGGER = logging.getLogger(__name__)

_SPORTS = (
    ("WNBA", "Sportradar WNBA"),
    ("NBA", "Sportradar NBA"),
    ("MLB", "MLB Stats API / SportsDataIO"),
    ("NFL", "Sportradar NFL"),
    ("NHL", "Sportradar NHL"),
    ("SOCCER", "Sportradar Soccer"),
)


def _persist_snapshot(snapshot: dict[str, object]) -> bool:
    """Persist the latest worker snapshot where every API instance can read it."""

    if not database_is_configured():
        return False
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """insert into provider_availability_snapshots(id, generated_at, payload)
                   values(true, %s, %s::jsonb)
                   on conflict(id) do update set
                     generated_at=excluded.generated_at,
                     payload=excluded.payload,
                     updated_at=now()""",
                (snapshot["generatedAt"], json.dumps(snapshot, default=str)),
            )
            connection.commit()
        return True
    except Exception as exc:
        LOGGER.warning("Provider availability database write failed error=%s", exc)
        return False


def _read_persisted_snapshot() -> dict[str, object] | None:
    if not database_is_configured():
        return None
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """select payload
                   from provider_availability_snapshots
                   where id=true
                   limit 1"""
            )
            row = cursor.fetchone()
        payload = row[0] if row else None
        if isinstance(payload, str):
            payload = json.loads(payload)
        return dict(payload) if isinstance(payload, dict) else None
    except Exception as exc:
        LOGGER.warning("Provider availability database read failed error=%s", exc)
        return None


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
    error = str(row.get("error") or "").lower()
    if "not entitled" in skipped:
        return "NOT_ENTITLED"
    if "not configured" in skipped:
        return "NOT_CONFIGURED"
    if "403" in error or "not entitled" in error:
        return "NOT_ENTITLED"
    if "429" in error or "too many requests" in error:
        return "THROTTLED"
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
        elif "THROTTLED" in authorizations:
            authorization = "THROTTLED"
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
        raw_errors = [str(row["error"]) for row in rows if row.get("error")]
        # A rejected or throttled supplemental source must not downgrade a
        # sport when another authorized provider completed successfully. Keep
        # raw provider diagnostics in `providers`, but reserve the public
        # missing-data alert for a true all-provider failure.
        errors = raw_errors if not authorized and authorization == "ERROR" else []
        missing: list[str] = []
        if authorization == "NOT_ENTITLED":
            missing.append("Provider plan does not include this sport.")
        elif authorization == "NOT_CONFIGURED":
            missing.append("Provider credentials are not configured.")
        elif authorization == "THROTTLED":
            missing.append("Optional provider is rate limited; fallback feeds remain active.")
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

        if authorization in {"NOT_ENTITLED", "NOT_CONFIGURED", "THROTTLED"}:
            status = "OPTIONAL"
        elif authorization == "ERROR":
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
        if status not in {"HEALTHY", "OPTIONAL"}:
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
    cache_stored = set_json(
        _CACHE_KEY, snapshot, ttl_seconds=_CACHE_TTL_SECONDS,
    )
    database_stored = _persist_snapshot(snapshot)
    snapshot["storage"] = {
        "redis": cache_stored,
        "database": database_stored,
        "durable": cache_stored or database_stored,
    }
    if not cache_stored and not database_stored:
        LOGGER.error(
            "Provider availability snapshot was not stored in Redis or PostgreSQL"
        )
    return snapshot


def provider_availability_snapshot(
    *, now: datetime | None = None,
) -> dict[str, object]:
    """Return the latest snapshot with freshness recalculated at read time."""

    current = _utc(now)
    shared = get_json(_CACHE_KEY)
    persisted = None if isinstance(shared, dict) else _read_persisted_snapshot()
    with _LOCAL_LOCK:
        payload = (
            shared
            if isinstance(shared, dict)
            else persisted
            if isinstance(persisted, dict)
            else _LOCAL_SNAPSHOT
        )
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
        authorization = str(item.get("authorizationStatus") or "").upper()
        if authorization in {"NOT_ENTITLED", "NOT_CONFIGURED", "THROTTLED"}:
            item["status"] = "OPTIONAL"
        last_attempt = item.get("lastAttemptAt")
        try:
            observed = datetime.fromisoformat(str(last_attempt).replace("Z", "+00:00"))
            stale = current - observed > timedelta(minutes=_STALE_MINUTES)
        except (TypeError, ValueError):
            stale = True
        item["stale"] = stale
        if stale and item.get("status") != "OPTIONAL":
            item["status"] = "UNAVAILABLE"
            missing = list(item.get("missingData") or [])
            if "Latest availability data is stale." not in missing:
                missing.append("Latest availability data is stale.")
            item["missingData"] = missing
        sports.append(item)
        if item.get("status") not in {"HEALTHY", "OPTIONAL"}:
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
