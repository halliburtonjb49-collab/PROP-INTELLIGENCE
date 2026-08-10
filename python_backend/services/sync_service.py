import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Callable

from config import DB_PATH
from database.cache import PropCache
from services.market_config import markets_for_sport
from services.odds_service import (
    record_historical_access,
    estimate_event_odds_cost, fetch_event_odds, fetch_events, quota_allows,
    record_sport_fetch, regions_for_sport,
)
from services.prop_processor import process_and_cache_props
from services.historical_ingestion_service import (
    run_gridiron_ice_backfill,
    run_nflverse_season_backfill,
)
from services.projection_backtest_service import record_projection_grade
from services.selectability_projection_service import (
    record_projection as record_selectability_projection,
)
from services.prediction_automation_service import (
    capture_prediction_closing_lines,
    snapshot_live_predictions,
)
from services.compound_alert_service import evaluate_all_alerts
from services.prop_service import get_props
from services.pregame_context_ingestion_service import sync_pregame_context
from config import (
    BALLDONTLIE_API_KEY,
    ODDS_EVENT_HORIZON_DAYS,
    ODDS_MINIMUM_EVENTS_PER_SPORT,
    SPORTSGAMEODDS_API_KEY,
)
from providers.sportsgameodds import (
    LEAGUE_TO_SPORT,
    fetch_account_usage as fetch_sgo_account_usage,
    fetch_upcoming_events as fetch_sgo_events,
    normalize_event as normalize_sgo_event,
    usage_snapshot as sgo_usage_snapshot,
)
from providers.balldontlie_soccer import (
    LEAGUE_TO_SPORT as BDL_SOCCER_LEAGUE_TO_SPORT,
    fetch_player_props as fetch_bdl_player_props,
    fetch_upcoming_matches as fetch_bdl_matches,
    normalize_match as normalize_bdl_match,
)
from providers.sportmonks_cricket import (
    cricketdata_health_check,
    probe_cricket_odds_shape,
)

cache = PropCache(DB_PATH)
logger = logging.getLogger(__name__)

DEFAULT_SYNC_SPORTS = (
    "baseball_mlb",
    "basketball_wnba",
    "basketball_nba",
    "americanfootball_nfl",
    "icehockey_nhl",
    "soccer_epl",
    "soccer_usa_mls",
    "soccer_france_ligue_one",
    "soccer_germany_bundesliga",
    "soccer_italy_serie_a",
    "soccer_spain_la_liga",
    "aussierules_afl",
    "rugbyleague_nrl",
)

DEFAULT_FAST_SYNC_SPORTS = (
    "baseball_mlb",
    "basketball_wnba",
    "basketball_nba",
    "americanfootball_nfl",
)
_coverage_lock = Lock()
_last_coverage_sync_monotonic: float | None = None
_sgo_cursor_lock = Lock()
_sgo_league_cursor = 0


def configured_sync_sports() -> list[str]:
    configured = os.getenv("PROP_SYNC_SPORTS", "").strip()
    candidates = configured.split(",") if configured else DEFAULT_SYNC_SPORTS
    return list(dict.fromkeys(value.strip() for value in candidates if value.strip()))


def partition_sync_sports(sports: list[str]) -> tuple[list[str], list[str]]:
    configured = os.getenv("PROP_FAST_SYNC_SPORTS", "").strip()
    candidates = configured.split(",") if configured else DEFAULT_FAST_SYNC_SPORTS
    fast_set = {value.strip() for value in candidates if value.strip()}
    return (
        [sport for sport in sports if sport in fast_set],
        [sport for sport in sports if sport not in fast_set],
    )


_gridiron_lock = Lock()
_last_gridiron_ingest_monotonic: float | None = None

_grade_lock = Lock()
_last_grade_monotonic: float | None = None


def _grade_due(now: float | None = None) -> bool:
    """Whether the projection grade is due its own replay.

    It has a separate cooldown because it was originally gated on the
    history top-up's, and the top-up marks that cooldown consumed before the
    grade is reached -- so the second check was always false and the grade
    never ran once. A gate that consumes its own precondition.
    """

    current = time.monotonic() if now is None else now
    interval = max(1800, int(os.getenv("PROJECTION_GRADE_SECONDS", "21600")))
    with _grade_lock:
        return (
            _last_grade_monotonic is None
            or current - _last_grade_monotonic >= interval
        )


def _mark_graded(now: float | None = None) -> None:
    global _last_grade_monotonic
    with _grade_lock:
        _last_grade_monotonic = time.monotonic() if now is None else now


def _gridiron_ingest_due(now: float | None = None) -> bool:
    """Whether NFL and NHL game logs are due a top-up.

    Their box-score ingestion was reachable only from an admin endpoint
    somebody had to remember to POST. Nothing called it on a schedule, so no
    NFL game logs existed at all, and 445 NFL props sat on the board with no
    projection behind any of them -- a coverage hole that looked like a model
    gap. Kept on a long cooldown because a day of box scores does not change
    between syncs, and walking it every few minutes would spend the request
    budget for nothing.
    """

    current = time.monotonic() if now is None else now
    interval = max(1800, int(os.getenv("GRIDIRON_INGEST_SECONDS", "21600")))
    with _gridiron_lock:
        return (
            _last_gridiron_ingest_monotonic is None
            or current - _last_gridiron_ingest_monotonic >= interval
        )


def _mark_gridiron_ingested(now: float | None = None) -> None:
    global _last_gridiron_ingest_monotonic
    with _gridiron_lock:
        _last_gridiron_ingest_monotonic = time.monotonic() if now is None else now


def _coverage_sync_due(now: float | None = None) -> bool:
    current = time.monotonic() if now is None else now
    interval = max(300, int(os.getenv("PROP_COVERAGE_SYNC_SECONDS", "1800")))
    with _coverage_lock:
        return (
            _last_coverage_sync_monotonic is None
            or current - _last_coverage_sync_monotonic >= interval
        )


def _mark_coverage_synced(now: float | None = None) -> None:
    global _last_coverage_sync_monotonic
    with _coverage_lock:
        _last_coverage_sync_monotonic = time.monotonic() if now is None else now


def next_sgo_leagues(limit: int | None = None) -> list[tuple[str, str]]:
    """Rotate limited provider calls so low rate limits cannot starve leagues."""
    global _sgo_league_cursor
    disabled = {
        value.strip().upper()
        for value in os.getenv(
            "SPORTSGAMEODDS_DISABLED_LEAGUES", ""
        ).split(",")
        if value.strip()
    }
    leagues = [
        item for item in LEAGUE_TO_SPORT.items()
        if item[0].upper() not in disabled
    ]
    if not leagues:
        return []
    # The product promises coverage across every enabled league. A stale
    # Render environment value previously limited each process to four and
    # repeatedly starved specialty sports after deploys. Explicit test/admin
    # limits still work, but normal production syncs always cover the catalog.
    configured_limit = limit if limit is not None else len(leagues)
    count = max(1, min(configured_limit, len(leagues)))
    with _sgo_cursor_lock:
        selected = [
            leagues[(_sgo_league_cursor + offset) % len(leagues)]
            for offset in range(count)
        ]
        _sgo_league_cursor = (_sgo_league_cursor + count) % len(leagues)
    return selected


def sgo_entity_quota_exhausted(usage: object) -> bool:
    if not isinstance(usage, dict):
        return False
    limits = usage.get("rateLimits")
    monthly = limits.get("per-month") if isinstance(limits, dict) else None
    if not isinstance(monthly, dict):
        return False
    maximum = monthly.get("max-entities")
    current = monthly.get("current-entities")
    return isinstance(maximum, int) and isinstance(current, int) and current >= maximum


def _with_retries(operation, *, attempts: int = 3, label: str = "provider call"):
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return operation()
        except Exception as exc:
            last_error = exc
            logger.warning("%s failed attempt=%s/%s error=%s", label, attempt, attempts, exc)
            if attempt < attempts:
                time.sleep(2 ** (attempt - 1))
    assert last_error is not None
    raise last_error


def _event_start(event: dict[str, object]) -> datetime:
    raw = event.get("commence_time") or event.get("commenceTime")
    try:
        parsed = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return datetime.max.replace(tzinfo=timezone.utc)
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=timezone.utc)


def prioritize_events(events: list[dict[str, object]]) -> list[dict[str, object]]:
    """Order valid events by start time so limited quota serves the nearest slate."""
    return sorted(events, key=lambda event: (_event_start(event), str(event.get("id", ""))))


# What _event_start returns when an event carries no usable start time.
_UNDATED = datetime.max.replace(tzinfo=timezone.utc)


def within_horizon(
    events: list[dict[str, object]], *, days: int, minimum: int = 0,
) -> tuple[list[dict[str, object]], int]:
    """Drop events starting further ahead than credits are worth spending on.

    Ordering alone does not help here. The nearest slate is already served
    first, but nothing stops the run from continuing through the rest of a
    published season, and each distant game costs exactly what tonight's
    does. In August the NFL lists all 272 regular-season games and returns
    1.6 props per event against MLB's 206, so the tail of that schedule
    spends most of the quota to produce almost nothing -- and the sports
    that come after it are reached with both keys exhausted.

    An event whose start time cannot be parsed is kept. We cannot show it is
    far away, and silently dropping a game we simply failed to read is the
    worse of the two mistakes.

    A date bound on its own deletes any sport whose season starts beyond the
    window, which is not what "too far away to be worth pricing" was meant to
    mean. `minimum` keeps the nearest few events of such a schedule so the
    sport stays on the board, while the rest of the season stays unpriced.
    """

    if days <= 0:
        return list(events), 0
    cutoff = datetime.now(timezone.utc) + timedelta(days=days)
    kept: list[dict[str, object]] = []
    deferred: list[dict[str, object]] = []
    for event in events:
        start = _event_start(event)
        if start != _UNDATED and start > cutoff:
            deferred.append(event)
        else:
            kept.append(event)
    if minimum > 0 and len(kept) < minimum:
        # Events arrive nearest-first, so the front of `deferred` is the
        # front of the schedule -- the part actually worth reaching for.
        shortfall = minimum - len(kept)
        kept.extend(deferred[:shortfall])
        deferred = deferred[shortfall:]
    return kept, len(deferred)


def sync_sport(sport_key: str) -> dict[str, object]:
    started_at = time.perf_counter()
    markets = markets_for_sport(sport_key)
    if not markets:
        logger.warning(
            "sync_sport skipped sport=%s reason=no_markets",
            sport_key,
        )
        # Recorded rather than returned silently. Without this the sport has
        # no entry at all and reads back as neverFetched -- the same answer a
        # sport nobody ever asked for gives, when the truth is that it was
        # asked for and has no markets configured to ask with.
        record_sport_fetch(
            sport_key, events=0, props=0, error="skipped: no markets configured",
        )
        return {
            "sport": sport_key,
            "events": 0,
            "props": 0,
        }

    events = prioritize_events(_with_retries(
        lambda: fetch_events(sport_key), label=f"events {sport_key}",
    ))
    events, beyond_horizon = within_horizon(
        events,
        days=ODDS_EVENT_HORIZON_DAYS,
        minimum=ODDS_MINIMUM_EVENTS_PER_SPORT,
    )
    if beyond_horizon:
        logger.info(
            "sync_sport horizon sport=%s kept=%s beyondHorizon=%s days=%s",
            sport_key, len(events), beyond_horizon, ODDS_EVENT_HORIZON_DAYS,
        )
    active_event_ids = [
        str(event.get("id", "")).strip()
        for event in events
        if str(event.get("id", "")).strip()
    ]
    if active_event_ids:
        cache.prune_sport_to_event_ids(
            sport=sport_key,
            active_event_ids=active_event_ids,
        )
    else:
        logger.warning(
            "sync_sport preserved cache sport=%s reason=no_active_events",
            sport_key,
        )
    prop_count = 0
    fetched_events = 0
    skipped_for_quota = 0
    failed_events = 0
    # Kept so a sport whose every request fails can say why. The log line
    # below already records it per event, but nothing outside the process
    # can read those, which left six soccer leagues failing silently.
    first_failure = ""
    estimated_event_cost = estimate_event_odds_cost(
        markets,
        regions=regions_for_sport(sport_key),
    )

    eligible_events: list[dict[str, object]] = []
    for event in events:
        event_id = str(event.get("id", ""))
        if not event_id:
            continue

        budget = quota_allows(estimated_event_cost * (len(eligible_events) + 1))
        if budget["allowed"] is not True:
            skipped_for_quota = len(events) - len(eligible_events)
            logger.warning(
                "sync_sport quota_guard sport=%s remaining=%s estimatedCost=%s reserve=%s skipped=%s",
                sport_key, budget["remaining"], estimated_event_cost,
                budget["reserve"], skipped_for_quota,
            )
            break
        eligible_events.append(event)

    def fetch_one(event: dict[str, object]):
        event_id = str(event.get("id", ""))
        try:
            payload = _with_retries(
                lambda: fetch_event_odds(
                    sport_key=sport_key,
                    event_id=event_id,
                    markets=markets,
                ),
                label=f"odds {sport_key} {event_id}",
            )
            return event, payload, None
        except Exception as exc:
            return event, None, exc

    configured_workers = max(1, int(os.getenv("PROP_SYNC_EVENT_WORKERS", "6")))
    worker_count = min(configured_workers, max(1, len(eligible_events)))
    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        fetched_payloads = executor.map(fetch_one, eligible_events)
        # Cache mutations stay serialized while network requests overlap.
        for event, odds_payload, error in fetched_payloads:
            event_id = str(event.get("id", ""))
            if error is not None or odds_payload is None:
                failed_events += 1
                if not first_failure and error is not None:
                    first_failure = f"{type(error).__name__}: {error}"[:200]
                logger.error(
                    "sync_event failed; preserving cached props sport=%s event=%s error=%s",
                    sport_key,
                    event_id,
                    error,
                )
                continue
            fetched_events += 1
            prop_count += process_and_cache_props(
                cache=cache,
                sport_key=sport_key,
                event=event,
                odds_payload=odds_payload,
            )

    elapsed_ms = int((time.perf_counter() - started_at) * 1000)
    logger.info(
        "sync_sport provider=odds_api sport=%s events=%s props=%s elapsedMs=%s",
        sport_key,
        len(events),
        prop_count,
        elapsed_ms,
    )

    # Recorded so an empty rail can be explained from outside the process:
    # a sport that returns games but no player markets looks identical to one
    # that is out of season, and to one nobody is asking for.
    record_sport_fetch(
        sport_key,
        events=len(events),
        props=prop_count,
        fetched_events=fetched_events,
        skipped_for_quota=skipped_for_quota,
        failed_events=failed_events,
        beyond_horizon=beyond_horizon,
        error=first_failure,
    )
    return {
        "sport": sport_key,
        "events": len(events),
        "fetchedEvents": fetched_events,
        "skippedForQuota": skipped_for_quota,
        "failedEvents": failed_events,
        "estimatedCostPerEvent": estimated_event_cost,
        "eventWorkers": worker_count,
        "props": prop_count,
    }


def sync_sportsgameodds() -> dict[str, object]:
    """Sync the supplemental multi-book player-prop feed."""
    if not SPORTSGAMEODDS_API_KEY:
        return {
            "sport": "sportsgameodds",
            "events": 0,
            "props": 0,
            "skipped": "not configured",
        }
    total_events = 0
    total_props = 0
    failures: list[dict[str, str]] = []
    account_usage: dict[str, object] | None = None
    try:
        account_usage = fetch_sgo_account_usage()
    except Exception as exc:
        logger.info("sportsgameodds usage unavailable error=%s", exc)
    if sgo_entity_quota_exhausted(account_usage):
        return {
            "sport": "sportsgameodds", "events": 0, "props": 0,
            "skipped": "monthly entity quota exhausted",
            "attemptedLeagues": [], "rotationSize": len(LEAGUE_TO_SPORT),
            "providerUsage": sgo_usage_snapshot(), "accountUsage": account_usage,
        }
    selected_leagues = next_sgo_leagues()
    def fetch_league(item: tuple[str, str]):
        league_id, sport_key = item
        try:
            raw_events = _with_retries(
                lambda league_id=league_id: fetch_sgo_events(league_id),
                label=f"sportsgameodds events {league_id}",
                attempts=2,
            )
            return league_id, sport_key, raw_events, None
        except Exception as exc:
            return league_id, sport_key, [], exc

    # Provider reads are independent and safe to overlap. Cache mutation stays
    # serialized below so SQLite/Postgres writes remain deterministic.
    league_workers = min(
        max(1, int(os.getenv("SPORTSGAMEODDS_LEAGUE_WORKERS", "4"))),
        max(1, len(selected_leagues)),
    )
    with ThreadPoolExecutor(max_workers=league_workers) as executor:
        fetched_leagues = list(executor.map(fetch_league, selected_leagues))

    league_results: list[dict[str, object]] = []
    for league_id, sport_key, raw_events, fetch_error in fetched_leagues:
        if fetch_error is not None:
            logger.warning(
                "sportsgameodds sync failed league=%s error=%s",
                league_id,
                fetch_error,
            )
            failures.append({"league": league_id, "error": str(fetch_error)})
            league_results.append({
                "league": league_id, "events": 0, "props": 0,
                "error": str(fetch_error),
            })
            continue
        try:
            normalized = [
                normalize_sgo_event(raw, sport_key=sport_key)
                for raw in raw_events
            ]
            valid_ids = [
                str(event.get("id") or "")
                for event, _ in normalized
                if event.get("id")
            ]
            if valid_ids:
                cache.prune_provider_events(
                    sport=sport_key,
                    event_prefix="sgo:",
                    active_event_ids=valid_ids,
                )
            else:
                # A temporary empty specialty response must not erase the
                # last healthy PGA/Tennis/UFC slate. Normal board expiry rules
                # still hide events after they start or finish.
                logger.warning(
                    "sportsgameodds preserved cache league=%s reason=no_active_events",
                    league_id,
                )
            league_props = 0
            for event, odds_payload in normalized:
                league_props += process_and_cache_props(
                    cache=cache,
                    sport_key=sport_key,
                    event=event,
                    odds_payload=odds_payload,
                )
            total_props += league_props
            total_events += len(normalized)
            league_results.append({
                "league": league_id,
                "events": len(normalized),
                "props": league_props,
            })
        except Exception as exc:
            logger.warning(
                "sportsgameodds sync failed league=%s error=%s",
                league_id,
                exc,
            )
            failures.append({"league": league_id, "error": str(exc)})
            league_results.append({
                "league": league_id, "events": len(raw_events), "props": 0,
                "error": str(exc),
            })
    return {
        "sport": "sportsgameodds",
        "events": total_events,
        "props": total_props,
        "failedLeagues": failures,
        "providerUsage": sgo_usage_snapshot(),
        "accountUsage": account_usage,
        "leagueResults": league_results,
        "attemptedLeagues": [league for league, _ in selected_leagues],
        "disabledLeagues": sorted({
            value.strip().upper()
            for value in os.getenv(
                "SPORTSGAMEODDS_DISABLED_LEAGUES", ""
            ).split(",")
            if value.strip()
        }),
        "rotationSize": len(LEAGUE_TO_SPORT),
    }


def sync_balldontlie_soccer() -> dict[str, object]:
    """Sync real player-prop lines for soccer leagues that the Odds API
    coverage lane has not been returning events for."""
    if not BALLDONTLIE_API_KEY:
        return {
            "sport": "balldontlie_soccer",
            "events": 0,
            "props": 0,
            "skipped": "not configured",
        }
    total_events = 0
    total_props = 0
    failures: list[dict[str, str]] = []
    league_results: list[dict[str, object]] = []

    def fetch_league(item: tuple[str, str]):
        league, sport_key = item
        try:
            raw_matches = _with_retries(
                lambda league=league: fetch_bdl_matches(league),
                label=f"balldontlie matches {league}",
                attempts=2,
            )
            return league, sport_key, raw_matches, None
        except Exception as exc:
            return league, sport_key, [], exc

    with ThreadPoolExecutor(max_workers=min(4, len(BDL_SOCCER_LEAGUE_TO_SPORT))) as executor:
        fetched_leagues = list(executor.map(fetch_league, BDL_SOCCER_LEAGUE_TO_SPORT.items()))

    for league, sport_key, raw_matches, fetch_error in fetched_leagues:
        if fetch_error is not None:
            logger.warning("balldontlie soccer sync failed league=%s error=%s", league, fetch_error)
            failures.append({"league": league, "error": str(fetch_error)})
            league_results.append({"league": league, "events": 0, "props": 0, "error": str(fetch_error)})
            continue
        upcoming = [m for m in raw_matches if str(m.get("status") or "").lower() not in {"final", "finished", "ft", "completed"}]

        def fetch_match_props(raw_match: dict[str, object]):
            match_id = raw_match.get("id")
            if match_id is None:
                return raw_match, None, None
            try:
                raw_props = _with_retries(
                    lambda league=league, match_id=match_id: fetch_bdl_player_props(league, match_id),
                    label=f"balldontlie player_props {league}:{match_id}",
                    attempts=2,
                )
                return raw_match, raw_props, None
            except Exception as exc:
                return raw_match, None, exc

        # Player-prop fetches are per-match HTTP calls; a league can easily
        # have 15-20 upcoming matches, so this must overlap or a single
        # sync cycle becomes the same kind of slow request the app was
        # already hurting from. Cache writes below stay serialized.
        with ThreadPoolExecutor(max_workers=min(8, max(1, len(upcoming)))) as match_executor:
            fetched_matches = list(match_executor.map(fetch_match_props, upcoming))

        league_props = 0
        valid_ids: list[str] = []
        for raw_match, raw_props, fetch_error in fetched_matches:
            if fetch_error is not None:
                logger.warning(
                    "balldontlie player_props failed league=%s match=%s error=%s",
                    league, raw_match.get("id"), fetch_error,
                )
                continue
            if raw_props is None:
                continue
            event, odds_payload = normalize_bdl_match(raw_match, raw_props, sport_key=sport_key)
            valid_ids.append(event["id"])
            league_props += process_and_cache_props(
                cache=cache,
                sport_key=sport_key,
                event=event,
                odds_payload=odds_payload,
            )
        if valid_ids:
            cache.prune_provider_events(
                sport=sport_key,
                event_prefix="bdl:",
                active_event_ids=valid_ids,
            )
        else:
            logger.warning(
                "balldontlie soccer preserved cache league=%s reason=no_upcoming_matches",
                league,
            )
        total_props += league_props
        total_events += len(upcoming)
        league_results.append({"league": league, "events": len(upcoming), "props": league_props})

    return {
        "sport": "balldontlie_soccer",
        "events": total_events,
        "props": total_props,
        "failedLeagues": failures,
        "leagueResults": league_results,
    }


def run_global_sync_pipeline(
    on_fast_lane_complete: Callable[[list[dict[str, object]]], None] | None = None,
) -> list[dict[str, object]]:
    sports = configured_sync_sports()
    fast_sports, coverage_sports = partition_sync_sports(sports)
    results: list[dict[str, object]] = []

    def sync_lane(lane_sports: list[str]) -> None:
        for sport_key in lane_sports:
            try:
                results.append(sync_sport(sport_key))
            except Exception as exc:
                logger.exception("sync_sport failed sport=%s", sport_key)
                # Recorded here as well as on success. The recorder used to
                # sit only on the success path, so a sport that threw looked
                # exactly like one nobody had asked for -- and nine of them
                # were reported as never fetched with no reason attached.
                record_sport_fetch(
                    sport_key,
                    events=0,
                    props=0,
                    error=f"{type(exc).__name__}: {exc}"[:200],
                )
                results.append({"sport": sport_key, "events": 0, "props": 0, "error": str(exc)})

    sync_lane(fast_sports)
    if on_fast_lane_complete is not None:
        try:
            on_fast_lane_complete(list(results))
        except Exception as exc:
            logger.warning("fast lane completion callback failed error=%s", exc)

    if _coverage_sync_due():
        sync_lane(coverage_sports)
        _mark_coverage_synced()
    else:
        for sport_key in coverage_sports:
            # A cooldown is not a failure and not an absence; say which.
            record_sport_fetch(
                sport_key, events=0, props=0, error="skipped: coverage cooldown"
            )
            results.append({
                "sport": sport_key,
                "events": 0,
                "props": 0,
                "lane": "coverage",
                "skipped": "coverage cooldown",
            })
    results.append(sync_sportsgameodds())
    results.append(sync_balldontlie_soccer())
    try:
        cricket_probe = probe_cricket_odds_shape()
    except Exception as exc:
        logger.warning("sportmonks cricket probe crashed error=%s", exc)
        cricket_probe = {"status": "error", "error": str(exc)}
    results.append({
        "sport": "sportmonks_cricket_probe", "events": 0, "props": 0,
        **cricket_probe,
    })
    try:
        cricketdata_probe = cricketdata_health_check()
    except Exception as exc:
        logger.warning("cricketdata.org health check crashed error=%s", exc)
        cricketdata_probe = {"status": "error", "error": str(exc)}
    results.append({
        "sport": "cricketdata_probe", "events": 0, "props": 0,
        **cricketdata_probe,
    })
    if _gridiron_ingest_due():
        try:
            # The first run after a deploy reaches back far enough to seed a
            # history that does not exist yet; later runs only top it up.
            # Without this the schedule keeps three days current forever and
            # the 445 NFL props with no projection stay that way, because
            # nothing was ever going to fetch the season behind them.
            seeded = _last_gridiron_ingest_monotonic is not None
            if not seeded:
                # Seed NFL from nflverse rather than walking eight months of
                # ESPN scoreboard a day at a time: one request per season,
                # and it carries air yards and EPA the box score lacks. NHL
                # still comes from the day-by-day walk below.
                try:
                    year = datetime.now(timezone.utc).year
                    seasons = tuple(
                        int(value)
                        for value in os.getenv(
                            "NFLVERSE_SEED_SEASONS", f"{year - 1},{year}"
                        ).split(",")
                        if value.strip()
                    )
                    nflverse = run_nflverse_season_backfill(seasons)
                    stored = sum(
                        int((entry or {}).get("stored") or 0)
                        for entry in (nflverse.get("seasons") or {}).values()
                    )
                    results.append({
                        "sport": "nflverse_history", "events": 0, "props": stored,
                    })
                except Exception as exc:
                    logger.warning("nflverse seed failed error=%s", exc)
            window = max(
                1,
                int(os.getenv("GRIDIRON_INGEST_DAYS", "3"))
                if seeded
                else int(os.getenv("GRIDIRON_SEED_DAYS", "240")),
            )
            gridiron = run_gridiron_ice_backfill(days=window)
            stored = sum(
                int((value or {}).get("stored") or 0)
                for key, value in gridiron.items()
                if isinstance(value, dict)
            )
            results.append({
                "sport": "gridiron_ice_history", "events": 0, "props": stored,
            })
        except Exception as exc:
            # A history top-up must never take the odds sync down with it.
            logger.warning("gridiron ingestion failed error=%s", exc)
            results.append({
                "sport": "gridiron_ice_history", "events": 0, "props": 0,
                "error": str(exc),
            })
        finally:
            _mark_gridiron_ingested()
    results.extend(sync_pregame_context())
    snapshot = snapshot_live_predictions()
    results.append({"sport": "prediction_snapshots", "events": 0,
                    "props": int(snapshot.get("created", 0))})
    # Guarded because it was not, and it is the last unguarded call in the
    # pipeline. When it raised, everything after it died with it: the
    # selectability projection never ran and no compound alert was ever
    # evaluated. From outside this looked like two features quietly doing
    # nothing, because the sync itself still reported success for the sports
    # it had already finished.
    try:
        clv = capture_prediction_closing_lines()
        results.append({"sport": "prediction_clv", "events": 0,
                        "props": int(clv.get("updated", 0))})
    except Exception as exc:
        logger.warning("closing line capture failed error=%s", exc)
        results.append({"sport": "prediction_clv", "events": 0, "props": 0,
                        "error": str(exc)})
    # Measured here because this walk already holds every prop; doing it
    # inside a request is what turned the operations endpoint into a 502.
    _board = get_props()
    record_selectability_projection(_board)
    # Graded on the same long cooldown as the history top-up: replaying
    # every stored game is expensive and its answer does not change
    # between syncs minutes apart.
    if _grade_due():
        try:
            record_historical_access()
        except Exception as exc:
            logger.warning("historical access probe failed error=%s", exc)
        try:
            record_projection_grade()
        except Exception as exc:
            logger.warning("projection grade failed error=%s", exc)
        finally:
            _mark_graded()
    alert_snapshots = [{
        "propId": prop.id, "player": prop.player, "playerId": prop.playerId,
        "sport": prop.sport, "market": prop.market, "marketKey": prop.marketKey,
        "line": prop.line, "side": prop.recommendedSide, "confidence": prop.confidence,
        "edge": prop.recommendationEdge, "injuryStatus": prop.injuryStatus,
        "lineupStatus": prop.lineupStatus, "gameId": prop.gameId,
    } for prop in _board]
    deliveries = evaluate_all_alerts(alert_snapshots)
    results.append({"sport": "compound_alerts", "events": len(alert_snapshots), "props": len(deliveries)})
    logger.info(
        "sync_global fast=%s coverage=%s",
        ",".join(fast_sports),
        ",".join(coverage_sports),
    )
    return results
