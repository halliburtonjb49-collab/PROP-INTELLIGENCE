"""Three-day provider reliability reporting for the live prop catalog."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta, timezone, tzinfo
from typing import Iterable


def _value(row: object, name: str, default: object = "") -> object:
    if isinstance(row, dict):
        return row.get(name, default)
    return getattr(row, name, default)


def _timestamp(value: object) -> datetime | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def provider_key(value: object) -> str:
    raw = str(value or "").strip().lower()
    compact = raw.replace(" ", "").replace("_", "").replace("-", "")
    aliases = {
        "betrusdfs": "BETR",
        "betr": "BETR",
        "draftkings": "DRAFTKINGS",
        "fanduel": "FANDUEL",
        "pick6": "PICK6",
        "pick06": "PICK6",
        "prizepicks": "PRIZEPICKS",
        "underdog": "UNDERDOG",
    }
    return aliases.get(compact, compact.upper())


def _event_key(row: object) -> str:
    for field in ("eventId", "gameId", "apiSportsGameId", "matchup"):
        value = str(_value(row, field, "") or "").strip()
        if value:
            return value
    return ""


def build_provider_reliability(
    props: Iterable[object],
    *,
    expected_sites: Iterable[str] = (),
    now_utc: datetime | None = None,
    horizon_days: int = 3,
    stale_after_minutes: int = 45,
    day_timezone: tzinfo | None = None,
) -> dict[str, object]:
    """Summarize provider freshness and slate coverage without exposing rows."""

    now = (now_utc or datetime.now(timezone.utc)).astimezone(timezone.utc)
    calendar_timezone = day_timezone or timezone.utc
    local_now = now.astimezone(calendar_timezone)
    horizon = max(1, horizon_days)
    cutoff = now + timedelta(days=horizon)
    expected = {
        provider_key(site)
        for site in expected_sites
        if provider_key(site)
    }

    providers: dict[str, dict[str, object]] = {}
    days: dict[str, dict[str, object]] = {}
    for offset in range(horizon):
        day = (local_now + timedelta(days=offset)).date().isoformat()
        days[day] = {
            "date": day,
            "propCount": 0,
            "events": set(),
            "providers": set(),
            "sports": set(),
        }

    all_events: set[str] = set()
    latest: datetime | None = None
    total_props = 0

    for prop in props:
        start = _timestamp(_value(prop, "startTimeUtc", ""))
        if start is None or start <= now or start > cutoff:
            continue
        day_key = start.astimezone(calendar_timezone).date().isoformat()
        day = days.get(day_key)
        if day is None:
            continue

        site = provider_key(_value(prop, "sportsbook", ""))
        if not site:
            continue
        expected.add(site)
        event = _event_key(prop)
        sport = str(_value(prop, "sport", "") or "").strip().upper()
        category = str(_value(prop, "category", "") or "").strip().upper()
        updated = _timestamp(_value(prop, "lastUpdatedUtc", ""))

        provider = providers.setdefault(
            site,
            {
                "propCount": 0,
                "events": set(),
                "sports": set(),
                "categories": set(),
                "latest": None,
            },
        )
        provider["propCount"] = int(provider["propCount"]) + 1
        if event:
            provider["events"].add(event)
            all_events.add(event)
            day["events"].add(event)
        if sport:
            provider["sports"].add(sport)
            day["sports"].add(sport)
        if category:
            provider["categories"].add(category)
        if updated is not None:
            current_latest = provider["latest"]
            if current_latest is None or updated > current_latest:
                provider["latest"] = updated
            if latest is None or updated > latest:
                latest = updated

        day["propCount"] = int(day["propCount"]) + 1
        day["providers"].add(site)
        total_props += 1

    provider_rows: list[dict[str, object]] = []
    stale_count = 0
    missing_count = 0
    unknown_freshness_count = 0
    for site in sorted(expected):
        data = providers.get(site)
        if data is None:
            missing_count += 1
            provider_rows.append(
                {
                    "provider": site,
                    "status": "MISSING",
                    "propCount": 0,
                    "eventCount": 0,
                    "sportCount": 0,
                    "categoryCount": 0,
                    "lastUpdatedAt": None,
                    "ageMinutes": None,
                }
            )
            continue

        provider_latest = data["latest"]
        age_minutes = (
            max(0, int((now - provider_latest).total_seconds() // 60))
            if isinstance(provider_latest, datetime)
            else None
        )
        if age_minutes is None:
            status = "UNKNOWN"
            unknown_freshness_count += 1
        elif age_minutes > stale_after_minutes:
            status = "STALE"
            stale_count += 1
        else:
            status = "LIVE"
        provider_rows.append(
            {
                "provider": site,
                "status": status,
                "propCount": int(data["propCount"]),
                "eventCount": len(data["events"]),
                "sportCount": len(data["sports"]),
                "categoryCount": len(data["categories"]),
                "lastUpdatedAt": (
                    provider_latest.isoformat().replace("+00:00", "Z")
                    if isinstance(provider_latest, datetime)
                    else None
                ),
                "ageMinutes": age_minutes,
            }
        )

    day_rows = [
        {
            "date": value["date"],
            "propCount": int(value["propCount"]),
            "eventCount": len(value["events"]),
            "providerCount": len(value["providers"]),
            "sportCount": len(value["sports"]),
        }
        for value in days.values()
    ]
    live_provider_count = sum(
        1 for row in provider_rows if int(row["propCount"]) > 0
    )
    expected_count = len(provider_rows)
    coverage_percent = (
        round(live_provider_count / expected_count * 100)
        if expected_count
        else 0
    )
    latest_age = (
        max(0, int((now - latest).total_seconds() // 60))
        if latest is not None
        else None
    )
    recovery_recommended = total_props == 0 or stale_count > 0
    status = (
        "EMPTY"
        if total_props == 0
        else "DEGRADED"
        if stale_count or unknown_freshness_count
        else "HEALTHY"
    )

    return {
        "status": status,
        "generatedAtUtc": now.isoformat().replace("+00:00", "Z"),
        "horizonDays": horizon,
        "staleAfterMinutes": stale_after_minutes,
        "totalProps": total_props,
        "eventCount": len(all_events),
        "providerCount": live_provider_count,
        "expectedProviderCount": expected_count,
        "providerCoveragePercent": coverage_percent,
        "latestDataUpdatedAt": (
            latest.isoformat().replace("+00:00", "Z") if latest else None
        ),
        "latestAgeMinutes": latest_age,
        "staleProviderCount": stale_count,
        "missingProviderCount": missing_count,
        "unknownFreshnessProviderCount": unknown_freshness_count,
        "recoveryRecommended": recovery_recommended,
        "providers": provider_rows,
        "days": day_rows,
    }
