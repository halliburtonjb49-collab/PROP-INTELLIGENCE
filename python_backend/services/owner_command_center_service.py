"""Lightweight, owner-only command-center overview and service monitor."""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from typing import Iterable, Mapping

from config import DB_PATH
from database.cache import PropCache
from database.postgres import database_is_configured, get_database_pool
from services.distributed_cache_service import health as cache_health
from services.espn_headshot_service import espn_headshot_cache_health
from services.job_queue_service import health as queue_health
from services.pipeline_run_service import recent_pipeline_runs, summarize_pipeline_health
from services.prop_catalog_snapshot_service import load_catalog_snapshot
from services.provider_availability_monitor_service import provider_availability_snapshot
from services.scoreboard_metrics_service import scoreboard_latency_snapshot
from services.owner_action_service import owner_action_snapshot, prop_control_key

_PROP_CACHE = PropCache(DB_PATH)
_WINDOWS = {"live", "today", "yesterday", "7d", "30d", "custom"}
_PRO_TIERS = ("pro", "edge", "gold", "pro_gold", "pro-gold")
_INVENTORY_LIMIT = 250
_STALE_LINE_MINUTES = 45


def _utc(value: datetime | None = None) -> datetime:
    current = value or datetime.now(timezone.utc)
    return current.astimezone(timezone.utc) if current.tzinfo else current.replace(tzinfo=timezone.utc)


def _parse_instant(value: str | None) -> datetime | None:
    if not value:
        return None
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return _utc(parsed)


def command_center_window(
    key: str,
    *,
    now: datetime | None = None,
    start: str | None = None,
    end: str | None = None,
) -> tuple[datetime, datetime, str]:
    current = _utc(now)
    normalized = str(key or "today").strip().lower()
    if normalized not in _WINDOWS:
        raise ValueError("Unsupported command-center time window")
    today = current.replace(hour=0, minute=0, second=0, microsecond=0)
    if normalized == "live":
        return current - timedelta(minutes=15), current, "Last 15 minutes"
    if normalized == "today":
        return today, current, "Today"
    if normalized == "yesterday":
        return today - timedelta(days=1), today, "Yesterday"
    if normalized == "7d":
        return current - timedelta(days=7), current, "Last 7 days"
    if normalized == "30d":
        return current - timedelta(days=30), current, "Last 30 days"
    custom_start, custom_end = _parse_instant(start), _parse_instant(end)
    if custom_start is None or custom_end is None or custom_start >= custom_end:
        raise ValueError("Custom range requires a valid start before end")
    if custom_end - custom_start > timedelta(days=366):
        raise ValueError("Custom range cannot exceed 366 days")
    return custom_start, custom_end, "Custom range"


def _database_metrics(start: datetime, end: datetime) -> dict[str, object]:
    metrics: dict[str, object] = {
        "available": False,
        "activeUsers": None,
        "newUsers": None,
        "totalUsers": None,
        "coreSubscribers": None,
        "proSubscribers": None,
        "predictionsGenerated": None,
        "apiRequests": None,
        "mrr": None,
        "mrrAvailable": False,
        "mrrNote": "MRR requires verified billing-period and complimentary-access separation.",
    }
    if not database_is_configured():
        return metrics
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """select count(distinct actor_hash)
                   from public.security_events
                   where occurred_at >= now() - interval '15 minutes'
                     and actor_hash is not null"""
            )
            metrics["activeUsers"] = int(cursor.fetchone()[0] or 0)
            cursor.execute(
                """select column_name from information_schema.columns
                   where table_schema='public' and table_name='user_profiles'"""
            )
            profile_columns = {str(row[0]) for row in cursor.fetchall()}
            if profile_columns:
                cursor.execute("select count(*) from public.user_profiles")
                metrics["totalUsers"] = int(cursor.fetchone()[0] or 0)
                if "created_at" in profile_columns:
                    cursor.execute(
                        """select count(*) from public.user_profiles
                           where created_at >= %s and created_at < %s""",
                        (start, end),
                    )
                    metrics["newUsers"] = int(cursor.fetchone()[0] or 0)
                if "subscription_tier" in profile_columns:
                    cursor.execute(
                        """select
                               count(*) filter(where lower(coalesce(subscription_tier,'')) = 'core'),
                               count(*) filter(where lower(coalesce(subscription_tier,'')) = any(%s))
                           from public.user_profiles""",
                        (list(_PRO_TIERS),),
                    )
                    core, pro = cursor.fetchone()
                    metrics["coreSubscribers"] = int(core or 0)
                    metrics["proSubscribers"] = int(pro or 0)
            if metrics["newUsers"] is None:
                cursor.execute(
                    "select to_regclass('public.member_signup_notifications') is not null"
                )
                if bool(cursor.fetchone()[0]):
                    cursor.execute(
                        """select count(*) from public.member_signup_notifications
                           where first_seen_at >= %s and first_seen_at < %s""",
                        (start, end),
                    )
                    metrics["newUsers"] = int(cursor.fetchone()[0] or 0)
            cursor.execute("select to_regclass('public.prediction_snapshots') is not null")
            if bool(cursor.fetchone()[0]):
                cursor.execute(
                    """select count(*) from public.prediction_snapshots
                       where created_at >= %s and created_at < %s""",
                    (start, end),
                )
                metrics["predictionsGenerated"] = int(cursor.fetchone()[0] or 0)
            cursor.execute(
                """select count(*) from public.security_events
                   where occurred_at >= %s and occurred_at < %s""",
                (start, end),
            )
            metrics["apiRequests"] = int(cursor.fetchone()[0] or 0)
            metrics["available"] = True
    except Exception as exc:
        metrics["error"] = type(exc).__name__
    return metrics


def _prop_metrics(rows: Iterable[object]) -> dict[str, object]:
    props = list(rows)
    sports: set[str] = set()
    live_games: set[str] = set()
    confidences: list[float] = []
    recommended = 0
    for row in props:
        sport = str(row["sport"] or "").strip().upper()
        if sport:
            sports.add(sport)
        status = str(row["game_status"] or "").strip().lower()
        if status in {"live", "in_progress", "in progress", "halftime", "intermission"}:
            live_games.add(str(row["game_id"] or ""))
        confidence = row["confidence"]
        if confidence is not None:
            numeric = float(confidence)
            if numeric > 1:
                numeric /= 100
            confidences.append(max(0.0, min(1.0, numeric)))
        prediction = str(row["prediction"] or "").strip().upper()
        if prediction and prediction not in {"WAIT", "PASS", "NO PLAY"}:
            recommended += 1
    return {
        "propsAvailable": len(props),
        "sportsActive": len(sports),
        "sportNames": sorted(sports),
        "gamesLive": len(live_games),
        "averageConfidence": round(sum(confidences) / len(confidences), 4) if confidences else None,
        "recommendedPicks": recommended,
    }



def _row_value(row: object, key: str, default: object = None) -> object:
    if isinstance(row, Mapping):
        return row.get(key, default)
    try:
        return row[key]  # type: ignore[index]
    except (IndexError, KeyError, TypeError):
        return default


def _first_row_value(row: object, *keys: str) -> object:
    for key in keys:
        value = _row_value(row, key)
        if value not in (None, ""):
            return value
    return None


def _instant(value: object) -> datetime | None:
    if value in (None, ""):
        return None
    try:
        return _parse_instant(str(value))
    except (TypeError, ValueError):
        return None


def _inventory_snapshot(
    rows: Iterable[object], *, now: datetime, limit: int = _INVENTORY_LIMIT,
) -> dict[str, object]:
    props = list(rows)
    duplicate_counts: Counter[tuple[str, str, str, str]] = Counter()
    market_lines: defaultdict[tuple[str, str, str], list[float]] = defaultdict(list)
    for row in props:
        game_id = str(_first_row_value(row, "game_id", "gameId", "event_id") or "")
        player = str(_first_row_value(row, "player_name", "player") or "").strip()
        market = str(_first_row_value(row, "prop_type", "market", "stat_type", "category") or "").strip()
        provider = str(_first_row_value(row, "bookmaker", "sportsbook", "source_provider", "provider") or "").strip()
        duplicate_counts[(game_id, player.lower(), market.lower(), provider.lower())] += 1
        current_line = _row_value(row, "current_line") or _row_value(row, "line")
        if current_line is not None:
            try:
                market_lines[(game_id, player.lower(), market.lower())].append(float(current_line))
            except (TypeError, ValueError):
                pass

    items: list[dict[str, object]] = []
    quality_counts: Counter[str] = Counter()
    provider_rollup: defaultdict[str, dict[str, object]] = defaultdict(
        lambda: {"props": 0, "sports": set(), "stale": 0, "suspicious": 0,
                 "missingProjection": 0, "lastUpdate": None}
    )
    flagged_total = 0
    for row in props:
        game_id = str(_first_row_value(row, "game_id", "gameId", "event_id") or "")
        player = str(_first_row_value(row, "player_name", "player") or "").strip()
        market = str(_first_row_value(row, "prop_type", "market", "stat_type", "category") or "").strip()
        provider = str(_first_row_value(row, "bookmaker", "sportsbook", "source_provider", "provider") or "Unknown").strip()
        sport = str(_row_value(row, "sport", "") or "Unknown").strip().upper()
        home = str(_row_value(row, "home_team", "") or "").strip()
        away = str(_row_value(row, "away_team", "") or "").strip()
        matchup = str(_first_row_value(row, "matchup", "game") or "").strip()
        prediction = str(_first_row_value(row, "prediction", "recommended_side", "recommendedSide", "pro_suggested_side") or "").strip().upper()
        confidence = _first_row_value(row, "confidence", "confidence_rating", "pi_trust_score", "piTrustScore")
        current_line = _row_value(row, "current_line") or _row_value(row, "line")
        opening_line = _row_value(row, "opening_line")
        updated_at = _instant(
            _row_value(row, "line_updated_at") or _row_value(row, "updated_at")
        )
        warnings: list[str] = []
        duplicate_key = (game_id, player.lower(), market.lower(), provider.lower())
        if game_id and duplicate_counts[duplicate_key] > 1:
            warnings.append("duplicate")
        if not player:
            warnings.append("missing_player")
        if (not home or not away) and not matchup:
            warnings.append("missing_matchup")
        if not prediction and confidence is None:
            warnings.append("missing_projection")
        if updated_at is not None and now - updated_at > timedelta(minutes=_STALE_LINE_MINUTES):
            warnings.append("stale_line")
        try:
            opening = float(opening_line) if opening_line is not None else None
            current = float(current_line) if current_line is not None else None
        except (TypeError, ValueError):
            opening, current = None, None
        line_delta = current - opening if opening is not None and current is not None else None
        suspicious_threshold = max(3.0, abs(opening or 0.0) * 0.35)
        if line_delta is not None and abs(line_delta) >= suspicious_threshold:
            warnings.append("extreme_line_change")
        peer_lines = market_lines[(game_id, player.lower(), market.lower())]
        if game_id and len(peer_lines) > 1 and max(peer_lines) - min(peer_lines) >= suspicious_threshold:
            warnings.append("provider_conflict")
        game_status = str(_row_value(row, "game_status", "") or "").strip().lower()
        if game_status in {"final", "completed", "cancelled", "canceled", "postponed"}:
            warnings.append("inactive_game")
        warnings = list(dict.fromkeys(warnings))
        quality_counts.update(warnings)
        if warnings:
            flagged_total += 1

        rollup = provider_rollup[provider]
        rollup["props"] = int(rollup["props"]) + 1
        sports = rollup["sports"]
        if isinstance(sports, set):
            sports.add(sport)
        if "stale_line" in warnings:
            rollup["stale"] = int(rollup["stale"]) + 1
        if "extreme_line_change" in warnings or "provider_conflict" in warnings:
            rollup["suspicious"] = int(rollup["suspicious"]) + 1
        if "missing_projection" in warnings:
            rollup["missingProjection"] = int(rollup["missingProjection"]) + 1
        previous_update = _instant(rollup["lastUpdate"])
        if updated_at is not None and (previous_update is None or updated_at > previous_update):
            rollup["lastUpdate"] = updated_at.isoformat()

        if len(items) < max(1, min(limit, 1000)):
            control_key = prop_control_key(
                sport=sport, game_id=game_id, player=player,
                market=market, provider=provider,
            )
            items.append({
                "id": control_key, "gameId": game_id,
                "sport": sport,
                "matchup": matchup or " vs ".join(value for value in (away, home) if value) or "Unknown matchup",
                "player": player or "Unknown player", "market": market or "Unknown market",
                "provider": provider, "line": current_line, "openingLine": opening_line,
                "lineMovement": round(line_delta, 3) if line_delta is not None else None,
                "prediction": prediction or None, "confidence": confidence,
                "gameStatus": game_status or "unknown",
                "lastUpdate": updated_at.isoformat() if updated_at else None,
                "warnings": warnings,
                "qualityStatus": "HEALTHY" if not warnings else "WARNING",
            })

    providers: list[dict[str, object]] = []
    for provider, values in sorted(
        provider_rollup.items(), key=lambda item: int(item[1]["props"]), reverse=True
    ):
        issue_count = int(values["stale"]) + int(values["suspicious"]) + int(values["missingProjection"])
        providers.append({
            "provider": provider, "status": "HEALTHY" if issue_count == 0 else "PARTIAL",
            "props": values["props"], "sports": sorted(values["sports"]),
            "stale": values["stale"], "suspicious": values["suspicious"],
            "missingProjection": values["missingProjection"], "lastUpdate": values["lastUpdate"],
        })

    facets = {
        "sports": sorted({str(item["sport"]) for item in items}),
        "providers": sorted({str(item["provider"]) for item in items}),
        "markets": sorted({str(item["market"]) for item in items}),
        "statuses": sorted({str(item["gameStatus"]) for item in items}),
        "quality": sorted(quality_counts),
    }
    alerts = [
        {"key": key, "count": count,
         "severity": "RED" if key in {"missing_projection", "provider_conflict"} else "GOLD"}
        for key, count in quality_counts.most_common()
    ]
    actions = owner_action_snapshot()
    quarantines = actions.get("quarantines") if isinstance(actions.get("quarantines"), Mapping) else {}
    acknowledgements = actions.get("acknowledgements") if isinstance(actions.get("acknowledgements"), Mapping) else {}
    for item in items:
        state = quarantines.get(str(item["id"])) if isinstance(quarantines, Mapping) else None
        item["quarantined"] = isinstance(state, Mapping)
        item["quarantine"] = dict(state) if isinstance(state, Mapping) else None
    for alert in alerts:
        alert_key = f"inventory:{alert['key']}"
        state = acknowledgements.get(alert_key) if isinstance(acknowledgements, Mapping) else None
        acknowledged = (
            isinstance(state, Mapping)
            and int(alert["count"]) <= int(state.get("count") or 0)
        )
        alert["id"] = alert_key
        alert["acknowledged"] = acknowledged
        alert["acknowledgement"] = dict(state) if acknowledged and isinstance(state, Mapping) else None
    flagged = flagged_total
    return {
        "total": len(props), "returned": len(items), "truncated": len(items) < len(props),
        "staleAfterMinutes": _STALE_LINE_MINUTES, "healthy": max(0, len(props) - flagged),
        "flagged": flagged, "facets": facets, "alerts": alerts,
        "providers": providers, "items": items,
        "quarantined": sum(1 for item in items if item.get("quarantined")),
        "ownerActionsAvailable": bool(actions.get("available")),
        "actionHistory": actions.get("history") or [],
    }
def _metric(key: str, label: str, value: object, detail: str, status: str = "healthy") -> dict[str, object]:
    return {"key": key, "label": label, "value": value, "detail": detail, "status": status}


def owner_command_center_snapshot(
    window: str = "today",
    *,
    start: str | None = None,
    end: str | None = None,
    now: datetime | None = None,
) -> dict[str, object]:
    current = _utc(now)
    range_start, range_end, range_label = command_center_window(
        window, now=current, start=start, end=end,
    )
    database = _database_metrics(range_start, range_end)
    rows: list[object] = []
    try:
        rows = list(_PROP_CACHE.load_props())
        if not rows:
            rows = load_catalog_snapshot()
        prop_metrics = _prop_metrics(rows)
    except Exception as exc:
        prop_metrics = {
            "propsAvailable": 0, "sportsActive": 0, "sportNames": [],
            "gamesLive": 0, "averageConfidence": None, "recommendedPicks": 0,
            "error": type(exc).__name__,
        }
    inventory = _inventory_snapshot(rows, now=current)
    from services.slip_service import get_slips
    current_by_id = {str(getattr(prop, "id", "")): prop for prop in rows}
    pi_recalculations = {"improved": 0, "weakened": 0, "updated": 0, "unchanged": 0}
    pi_recalculation_details: list[dict[str, object]] = []
    for slip in get_slips("active"):
        for leg in slip.legs:
            prop = current_by_id.get(leg.prop_id)
            current_projection = getattr(prop, "projection", None)
            current_confidence = getattr(prop, "confidence", None)
            projection_delta = (
                float(current_projection) - float(leg.projection)
                if current_projection is not None and leg.projection is not None else 0.0
            )
            confidence_delta = (
                int(current_confidence) - int(leg.confidence)
                if current_confidence is not None and leg.confidence is not None else 0
            )
            if projection_delta:
                improved = projection_delta > 0 if leg.side == "OVER" else projection_delta < 0
                key = "improved" if improved else "weakened"
            elif confidence_delta:
                key = "improved" if confidence_delta > 0 else "weakened"
            elif prop is not None and (
                str(getattr(prop, "injuryStatus", "unknown")) != leg.injury_status
                or str(getattr(prop, "lineupStatus", "unknown")) != leg.lineup_status
            ):
                key = "updated"
            else:
                key = "unchanged"
            pi_recalculations[key] += 1
            if key in {"improved", "weakened"}:
                pi_recalculation_details.append({
                    "slipId": slip.id, "propId": leg.prop_id, "player": leg.player,
                    "sport": leg.sport, "market": leg.market, "side": leg.side,
                    "line": leg.line, "entryProjection": leg.projection,
                    "currentProjection": current_projection,
                    "entryConfidence": leg.confidence, "currentConfidence": current_confidence,
                    "status": key.upper(),
                })
    learning_groups: dict[str, dict[str, object]] = {}
    for slip in get_slips():
        for leg in slip.legs:
            if leg.pi_recalculation_correct is None:
                continue
            group_key = f"{leg.sport}|{leg.market}"
            group = learning_groups.setdefault(group_key, {
                "sport": leg.sport, "market": leg.market, "sampleSize": 0,
                "correct": 0, "entryError": 0.0, "recalculatedError": 0.0,
            })
            group["sampleSize"] = int(group["sampleSize"]) + 1
            group["correct"] = int(group["correct"]) + int(leg.pi_recalculation_correct)
            group["entryError"] = float(group["entryError"]) + float(leg.pi_entry_error or 0)
            group["recalculatedError"] = float(group["recalculatedError"]) + float(leg.pi_recalculated_error or 0)
    pi_learning = []
    for group in learning_groups.values():
        sample = int(group["sampleSize"])
        pi_learning.append({
            **group,
            "accuracy": round(int(group["correct"]) / sample * 100, 1),
            "entryMae": round(float(group["entryError"]) / sample, 3),
            "recalculatedMae": round(float(group["recalculatedError"]) / sample, 3),
        })
    pi_learning.sort(key=lambda item: (-int(item["sampleSize"]), str(item["sport"]), str(item["market"])))
    redis = cache_health()
    workers = queue_health()
    worker_online = bool(
        workers.get("available")
        and int(workers.get("workers") or 0) > 0
    )
    worker_alerts = [] if worker_online else [{
        "key": "worker_unavailable",
        "title": "Background worker unavailable",
        "message": (
            "Saved props remain available, but provider refreshes and "
            "headshot updates are paused until a worker is online."
        ),
        "severity": "RED",
        "count": 1,
    }]
    scoreboard = scoreboard_latency_snapshot()
    pipeline = summarize_pipeline_health(recent_pipeline_runs(25))
    availability = provider_availability_snapshot(now=current)
    provider_alerts = list(availability.get("alerts") or [])
    active_failures = list(pipeline.get("activeFailures") or [])
    headshots = espn_headshot_cache_health(now=current)
    headshot_alerts = []
    if headshots.get("status") != "ok" or headshots.get("stale") is True:
        age = headshots.get("ageHours")
        age_detail = f" ({age}h old)" if age is not None else ""
        headshot_alerts.append({
            "key": "headshot_cache_stale",
            "title": "Athlete photo refresh needs attention",
            "message": (
                "The ESPN athlete-photo cache missed its expected daily "
                f"refresh{age_detail}. Existing portraits remain protected."
            ),
            "severity": "YELLOW",
            "count": 1,
        })

    overview = [
        _metric("activeUsers", "Active users", database.get("activeUsers"), "Authenticated activity in the last 15 minutes", "healthy" if database.get("activeUsers") is not None else "unavailable"),
        _metric("newUsers", "New users", database.get("newUsers"), range_label, "healthy" if database.get("newUsers") is not None else "unavailable"),
        _metric("coreSubscribers", "Core members", database.get("coreSubscribers"), "Current trusted profile tier", "healthy" if database.get("coreSubscribers") is not None else "unavailable"),
        _metric("proSubscribers", "Pro members", database.get("proSubscribers"), "Includes legacy Edge aliases", "healthy" if database.get("proSubscribers") is not None else "unavailable"),
        _metric("mrr", "Monthly recurring revenue", database.get("mrr"), str(database.get("mrrNote") or "Not connected"), "unavailable"),
        _metric("propsAvailable", "Props available", prop_metrics.get("propsAvailable"), "Current cache inventory"),
        _metric("sportsActive", "Sports active", prop_metrics.get("sportsActive"), ", ".join(prop_metrics.get("sportNames") or []) or "No active sports"),
        _metric("gamesLive", "Games live", prop_metrics.get("gamesLive"), "Based on authoritative game status"),
        _metric("predictionsGenerated", "Predictions generated", database.get("predictionsGenerated"), range_label, "healthy" if database.get("predictionsGenerated") is not None else "unavailable"),
        _metric("apiRequests", "Tracked API activity", database.get("apiRequests"), range_label, "healthy" if database.get("apiRequests") is not None else "unavailable"),
        _metric("averageConfidence", "Average confidence", prop_metrics.get("averageConfidence"), "Across current props"),
        _metric("recommendedPicks", "Recommended picks", prop_metrics.get("recommendedPicks"), "Current non-wait predictions"),
        _metric("piImproved", "PI improved", pi_recalculations["improved"], "Active watched recommendations strengthened"),
        _metric("piWeakened", "PI weakened", pi_recalculations["weakened"], "Active watched recommendations needing review", "warning" if pi_recalculations["weakened"] else "healthy"),
        _metric("piUpdated", "PI context updates", pi_recalculations["updated"], "Active injury or lineup evidence changes"),
        _metric("openAlerts", "Open alerts", len(worker_alerts) + len(provider_alerts) + len(active_failures) + len(headshot_alerts), "Worker, provider, pipeline, and photo-refresh alerts", "healthy" if not worker_alerts and not provider_alerts and not active_failures and not headshot_alerts else "warning"),
    ]

    services = [
        {"service": "API", "status": "HEALTHY", "lastUpdate": current.isoformat(), "latencyMs": None, "records": "online", "action": "View"},
        {"service": "Redis", "status": "HEALTHY" if redis.get("available") else "UNAVAILABLE", "lastUpdate": current.isoformat(), "latencyMs": None, "records": redis.get("mode") or "--", "action": "Inspect"},
        {"service": "Workers", "status": "HEALTHY" if worker_online and not workers.get("failed") else "UNAVAILABLE", "lastUpdate": current.isoformat(), "latencyMs": None, "records": f"{workers.get('workers', 0)} online / {workers.get('queued', 0)} queued", "action": "Inspect"},
        {"service": "Scoreboard", "status": "HEALTHY" if scoreboard.get("status") == "ok" else "PARTIAL", "lastUpdate": current.isoformat(), "latencyMs": scoreboard.get("lastMs"), "records": f"{scoreboard.get('sampleCount', 0)} samples", "action": "View"},
        {"service": "Prop inventory", "status": "HEALTHY" if prop_metrics.get("propsAvailable") else "PARTIAL", "lastUpdate": current.isoformat(), "latencyMs": None, "records": prop_metrics.get("propsAvailable", 0), "action": "View"},
        {"service": "Athlete photos", "status": "PARTIAL" if headshots.get("stale") else "HEALTHY", "lastUpdate": headshots.get("updatedAtUtc"), "latencyMs": None, "records": headshots.get("playerCount", 0), "action": "Refresh" if headshots.get("stale") else "Inspect"},
        {"service": "Model engine", "status": "HEALTHY" if database.get("predictionsGenerated") is not None else "UNAVAILABLE", "lastUpdate": current.isoformat(), "latencyMs": None, "records": database.get("predictionsGenerated"), "action": "Audit"},
    ]
    for sport in availability.get("sports") or []:
        if not isinstance(sport, dict):
            continue
        services.append({
            "service": f"{sport.get('sport', '--')} availability",
            "status": sport.get("status", "UNAVAILABLE"),
            "lastUpdate": sport.get("lastSuccessfulSync") or sport.get("lastAttemptAt"),
            "latencyMs": None,
            "records": sport.get("observationsFound", 0),
            "action": "Inspect",
            "detail": (sport.get("missingData") or [sport.get("detail") or ""])[0],
        })

    return {
        "generatedAt": current.isoformat(),
        "window": {"key": window, "label": range_label, "start": range_start.isoformat(), "end": range_end.isoformat()},
        "overview": overview,
        "services": services,
        "alerts": [*worker_alerts, *provider_alerts, *headshot_alerts, *active_failures],
        "database": database,
        "propInventory": prop_metrics,
        "inventory": inventory,
        "piRecalculations": pi_recalculations,
        "piRecalculationDetails": pi_recalculation_details[:100],
        "piRecalculationLearning": pi_learning[:100],
        "headshots": headshots,
    }
