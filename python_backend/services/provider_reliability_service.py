"""Provider reliability, market health, and four-date slate reporting."""

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
        "betrusdfs": "BETR", "betr": "BETR", "draftkings": "DRAFTKINGS",
        "fanduel": "FANDUEL", "pick6": "PICK6", "pick06": "PICK6",
        "prizepicks": "PRIZEPICKS", "underdog": "UNDERDOG",
    }
    return aliases.get(compact, compact.upper())


def _event_key(row: object) -> str:
    for field in ("eventId", "gameId", "apiSportsGameId", "matchup"):
        value = str(_value(row, field, "") or "").strip()
        if value:
            return value
    return ""


def build_provider_reliability(
    props: Iterable[object], *, expected_sites: Iterable[str] = (),
    now_utc: datetime | None = None, horizon_days: int = 4,
    stale_after_minutes: int = 45, day_timezone: tzinfo | None = None,
    refresh_interval_minutes: int = 15,
) -> dict[str, object]:
    """Summarize provider freshness and today-plus-three future slate coverage."""

    now = (now_utc or datetime.now(timezone.utc)).astimezone(timezone.utc)
    calendar_timezone = day_timezone or timezone.utc
    local_now = now.astimezone(calendar_timezone)
    horizon = max(1, horizon_days)
    cutoff = now + timedelta(days=horizon)
    expected = {provider_key(site) for site in expected_sites if provider_key(site)}

    providers: dict[str, dict[str, object]] = {}
    days: dict[str, dict[str, object]] = {}
    market_totals: dict[tuple[str, str], dict[str, object]] = {}
    for offset in range(horizon):
        day_key = (local_now + timedelta(days=offset)).date().isoformat()
        days[day_key] = {
            "date": day_key, "propCount": 0, "events": set(), "providers": set(),
            "sports": set(), "categories": set(), "providerCategories": defaultdict(set),
            "starts": [], "latest": None,
        }

    all_events: set[str] = set()
    latest: datetime | None = None
    total_props = 0
    for prop in props:
        start = _timestamp(_value(prop, "startTimeUtc", ""))
        if start is None or start <= now or start > cutoff:
            continue
        day = days.get(start.astimezone(calendar_timezone).date().isoformat())
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

        provider = providers.setdefault(site, {
            "propCount": 0, "events": set(), "sports": set(), "categories": set(), "latest": None,
        })
        provider["propCount"] = int(provider["propCount"]) + 1
        if event:
            provider["events"].add(event); all_events.add(event); day["events"].add(event)
        if sport:
            provider["sports"].add(sport); day["sports"].add(sport)
        if category:
            provider["categories"].add(category); day["categories"].add(category)
            day["providerCategories"][site].add(category)
            market = market_totals.setdefault((sport or "OTHER", category), {"providers": set(), "propCount": 0})
            market["providers"].add(site)
            market["propCount"] = int(market["propCount"]) + 1
        if updated is not None:
            if provider["latest"] is None or updated > provider["latest"]:
                provider["latest"] = updated
            if day["latest"] is None or updated > day["latest"]:
                day["latest"] = updated
            if latest is None or updated > latest:
                latest = updated
        day["propCount"] = int(day["propCount"]) + 1
        day["providers"].add(site)
        day["starts"].append(start)
        total_props += 1

    provider_rows: list[dict[str, object]] = []
    stale_count = missing_count = unknown_freshness_count = 0
    for site in sorted(expected):
        data = providers.get(site)
        if data is None:
            missing_count += 1
            provider_rows.append({
                "provider": site, "status": "MISSING", "propCount": 0,
                "eventCount": 0, "sportCount": 0, "categoryCount": 0,
                "lastUpdatedAt": None, "ageMinutes": None,
            })
            continue
        provider_latest = data["latest"]
        age_minutes = max(0, int((now-provider_latest).total_seconds()//60)) if isinstance(provider_latest, datetime) else None
        if age_minutes is None:
            status = "UNKNOWN"; unknown_freshness_count += 1
        elif age_minutes > stale_after_minutes:
            status = "STALE"; stale_count += 1
        else:
            status = "LIVE"
        provider_rows.append({
            "provider": site, "status": status, "propCount": int(data["propCount"]),
            "eventCount": len(data["events"]), "sportCount": len(data["sports"]),
            "categoryCount": len(data["categories"]),
            "lastUpdatedAt": provider_latest.isoformat().replace("+00:00", "Z") if isinstance(provider_latest, datetime) else None,
            "ageMinutes": age_minutes,
        })

    expected_count = len(expected)
    day_rows: list[dict[str, object]] = []
    for day in days.values():
        observed_providers = set(day["providers"])
        missing_providers = sorted(expected - observed_providers)
        coverage = round(len(observed_providers) / expected_count * 100) if expected_count else 0
        potential_missing: list[dict[str, object]] = []
        for site in sorted(observed_providers):
            known = set(providers.get(site, {}).get("categories", set()))
            observed = set(day["providerCategories"].get(site, set()))
            missing_categories = sorted(known - observed)
            if missing_categories:
                potential_missing.append({"provider": site, "categories": missing_categories[:8]})
        starts = sorted(day["starts"])
        first_start = starts[0] if starts else None
        lineup_at = first_start - timedelta(minutes=90) if first_start else None
        day_latest = day["latest"]
        day_rows.append({
            "date": day["date"], "propCount": int(day["propCount"]),
            "eventCount": len(day["events"]), "providerCount": len(observed_providers),
            "providerCoveragePercent": coverage, "sportCount": len(day["sports"]),
            "categoryCount": len(day["categories"]), "missingProviders": missing_providers,
            "potentialMissingMarkets": potential_missing,
            "potentialMissingMarketCount": sum(len(row["categories"]) for row in potential_missing),
            "firstEventAtUtc": first_start.isoformat().replace("+00:00", "Z") if first_start else None,
            "expectedLineupsAtUtc": lineup_at.isoformat().replace("+00:00", "Z") if lineup_at else None,
            "lastSuccessfulSyncAtUtc": day_latest.isoformat().replace("+00:00", "Z") if isinstance(day_latest, datetime) else None,
        })

    market_health = []
    for (sport, category), data in sorted(market_totals.items()):
        provider_count = len(data["providers"])
        coverage = round(provider_count / expected_count * 100) if expected_count else 0
        status = "GREEN" if coverage >= 75 else "YELLOW" if coverage >= 40 else "RED"
        market_health.append({
            "sport": sport, "category": category, "status": status,
            "providerCount": provider_count, "expectedProviderCount": expected_count,
            "coveragePercent": coverage, "propCount": int(data["propCount"]),
        })
    market_health.sort(key=lambda row: (row["sport"], row["status"], -int(row["propCount"]), row["category"]))

    live_provider_count = sum(1 for row in provider_rows if int(row["propCount"]) > 0)
    coverage_percent = round(live_provider_count / len(provider_rows) * 100) if provider_rows else 0
    latest_age = max(0, int((now-latest).total_seconds()//60)) if latest else None
    recovery_recommended = total_props == 0 or stale_count > 0
    status = "EMPTY" if total_props == 0 else "DEGRADED" if stale_count or unknown_freshness_count else "HEALTHY"
    next_refresh = now + timedelta(minutes=max(1, refresh_interval_minutes))

    return {
        "status": status, "generatedAtUtc": now.isoformat().replace("+00:00", "Z"),
        "horizonDays": horizon, "futureDays": max(0, horizon-1),
        "staleAfterMinutes": stale_after_minutes, "refreshIntervalMinutes": max(1, refresh_interval_minutes),
        "nextAutoRefreshAtUtc": next_refresh.isoformat().replace("+00:00", "Z"),
        "totalProps": total_props, "eventCount": len(all_events),
        "providerCount": live_provider_count, "expectedProviderCount": len(provider_rows),
        "providerCoveragePercent": coverage_percent,
        "latestDataUpdatedAt": latest.isoformat().replace("+00:00", "Z") if latest else None,
        "latestAgeMinutes": latest_age, "staleProviderCount": stale_count,
        "missingProviderCount": missing_count, "unknownFreshnessProviderCount": unknown_freshness_count,
        "recoveryRecommended": recovery_recommended, "providers": provider_rows,
        "days": day_rows, "marketHealth": market_health,
    }