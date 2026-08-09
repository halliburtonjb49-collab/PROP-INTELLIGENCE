"""Deterministic production-data acceptance checks for the live prop catalog."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Iterable


def _value(row: object, key: str, default: object = None) -> object:
    if isinstance(row, dict):
        return row.get(key, default)
    try:
        return row[key]  # type: ignore[index]
    except (KeyError, IndexError, TypeError):
        return getattr(row, key, default)


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


def _provider(value: object) -> str:
    compact = str(value or "").strip().lower().replace(" ", "").replace("_", "").replace("-", "")
    aliases = {"betrusdfs": "BETR", "betr": "BETR", "pick06": "PICK6"}
    return aliases.get(compact, compact.upper())


def _check(key: str, label: str, status: str, value: object, detail: str) -> dict[str, object]:
    return {"key": key, "label": label, "status": status, "value": value, "detail": detail}


def production_data_certification(
    rows: Iterable[object], *, expected_providers: Iterable[str] = (),
    now_utc: datetime | None = None, stale_after_minutes: int = 45,
    horizon_days: int = 4,
) -> dict[str, object]:
    """Grade live data without exposing proprietary prop rows."""

    now = (now_utc or datetime.now(timezone.utc)).astimezone(timezone.utc)
    horizon = max(1, horizon_days)
    cutoff = now + timedelta(days=horizon)
    expected = {_provider(value) for value in expected_providers if _provider(value)}
    providers: set[str] = set()
    provider_categories: dict[tuple[str, str], set[str]] = defaultdict(set)
    sport_categories: dict[str, set[str]] = defaultdict(set)
    days = {(now + timedelta(days=offset)).date().isoformat(): {"events": set(), "props": 0, "providers": set()} for offset in range(horizon)}
    latest: datetime | None = None
    total = tracked_lines = moved_lines = stale_rows = 0

    for row in rows:
        total += 1
        provider = _provider(_value(row, "bookmaker", _value(row, "sportsbook", "")))
        sport = str(_value(row, "sport", "") or "").strip().upper()
        category = str(_value(row, "prop_type", _value(row, "category", "")) or "").strip().upper()
        updated = _timestamp(_value(row, "updated_at", _value(row, "lastUpdatedUtc", "")))
        start = _timestamp(_value(row, "commence_time", _value(row, "startTimeUtc", "")))
        opening = _value(row, "opening_line", _value(row, "openingLine", None))
        current = _value(row, "current_line", _value(row, "currentLine", _value(row, "line", None)))
        if provider:
            providers.add(provider)
        if sport and category and provider:
            provider_categories[(sport, provider)].add(category)
            sport_categories[sport].add(category)
        if updated is not None:
            latest = updated if latest is None or updated > latest else latest
            if (now - updated).total_seconds() > stale_after_minutes * 60:
                stale_rows += 1
        try:
            opening_number, current_number = float(opening), float(current)
            if opening_number != 0 and current_number != 0:
                tracked_lines += 1
                if abs(opening_number - current_number) >= .01:
                    moved_lines += 1
        except (TypeError, ValueError):
            pass
        if start is not None and now <= start < cutoff:
            day = days.get(start.date().isoformat())
            if day is not None:
                day["props"] = int(day["props"]) + 1
                day["providers"].add(provider)
                event = str(_value(row, "game_id", _value(row, "eventId", "")) or "")
                if event:
                    day["events"].add(event)

    expected |= providers
    age_minutes = None if latest is None else max(0, int((now - latest).total_seconds() // 60))
    stale_ratio = stale_rows / total if total else 1.0
    provider_ratio = len(providers) / len(expected) if expected else 0.0
    line_ratio = tracked_lines / total if total else 0.0
    day_rows = [{
        "date": key, "propCount": int(value["props"]), "eventCount": len(value["events"]),
        "providerCount": len(value["providers"]),
        "status": "PASS" if int(value["props"]) > 0 else ("FAIL" if index == 0 else "WARN"),
    } for index, (key, value) in enumerate(days.items())]
    covered_days = sum(1 for day in day_rows if int(day["propCount"]) > 0)

    parity_issues = []
    for (sport, provider), categories in sorted(provider_categories.items()):
        benchmark = sport_categories[sport]
        ratio = len(categories) / len(benchmark) if benchmark else 1.0
        if ratio < .6:
            parity_issues.append({
                "sport": sport, "provider": provider, "coveragePercent": round(ratio * 100),
                "missingCategories": sorted(benchmark - categories)[:8],
            })

    checks = [
        _check("catalog", "Live catalog", "PASS" if total > 0 else "FAIL", total, f"{total} current prop rows are available."),
        _check("freshness", "Feed freshness", "FAIL" if age_minutes is None or age_minutes > stale_after_minutes * 2 else "WARN" if age_minutes > stale_after_minutes or stale_ratio > .25 else "PASS", age_minutes, f"Newest row is {age_minutes if age_minutes is not None else 'unknown'} minutes old; {round(stale_ratio * 100)}% of rows exceed the freshness SLA."),
        _check("providers", "Provider delivery", "PASS" if provider_ratio >= .75 else "WARN" if provider_ratio >= .5 else "FAIL", f"{len(providers)}/{len(expected)}", f"Missing configured providers: {', '.join(sorted(expected - providers)) or 'none'}."),
        _check("parity", "Category parity", "PASS" if not parity_issues else "WARN" if len(parity_issues) <= 2 else "FAIL", len(parity_issues), f"{len(parity_issues)} provider/sport combinations are below 60% of the observed market benchmark."),
        _check("slate", "Four-date slate", "PASS" if covered_days == horizon else "WARN" if day_rows and day_rows[0]["status"] == "PASS" else "FAIL", f"{covered_days}/{horizon}", f"Props are available on {covered_days} of {horizon} monitored dates."),
        _check("lines", "Line-history coverage", "PASS" if line_ratio >= .95 else "WARN" if line_ratio >= .75 else "FAIL", f"{round(line_ratio * 100)}%", f"{tracked_lines} rows have durable opening/current lines; {moved_lines} currently show movement."),
    ]
    failed = sum(1 for check in checks if check["status"] == "FAIL")
    warned = sum(1 for check in checks if check["status"] == "WARN")
    score = round(sum({"PASS": 1.0, "WARN": .5, "FAIL": 0.0}[str(check["status"])] for check in checks) / len(checks) * 100)
    return {
        "status": "FAIL" if failed else "WARN" if warned else "PASS", "score": score,
        "generatedAtUtc": now.isoformat().replace("+00:00", "Z"),
        "passCount": len(checks) - failed - warned, "warningCount": warned, "failureCount": failed,
        "checks": checks, "days": day_rows, "parityIssues": parity_issues[:12],
    }
