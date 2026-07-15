from typing import Any
from datetime import datetime, timezone
import logging

from calculations.prediction import calculate_prediction
from database.cache import PropCache

logger = logging.getLogger(__name__)


def _normalize_event_status(event: dict[str, Any]) -> str:
    raw = str(event.get("status") or event.get("state") or "").strip().lower()
    if raw:
        if "postpon" in raw:
            return "postponed"
        if "cancel" in raw:
            return "canceled"
        if "delay" in raw:
            return "delayed"
        if raw in {"final", "completed", "closed"}:
            return "final"
        if raw in {"in_progress", "live", "ongoing"}:
            return "live"
        if raw in {"scheduled", "not_started", "upcoming"}:
            return "scheduled"
    if bool(event.get("completed")):
        return "final"
    return "scheduled"


def _find_price(
    outcomes: list[dict[str, Any]],
    outcome_name: str,
) -> float | None:
    for outcome in outcomes:
        if str(outcome.get("name", "")).lower() == outcome_name.lower():
            price = outcome.get("price")
            if isinstance(price, (int, float)):
                return float(price)
    return None


def process_and_cache_props(
    *,
    cache: PropCache,
    sport_key: str,
    event: dict[str, Any],
    odds_payload: dict[str, Any],
) -> int:
    event_id = str(event.get("id", ""))
    if not event_id:
        return 0

    updated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    previous_snapshots = cache.get_existing_prop_snapshots(game_id=event_id)
    cache.replace_games(
        sport_key,
        [
            {
                "id": event_id,
                "home_team": event.get("home_team", ""),
                "away_team": event.get("away_team", ""),
                "commence_time": event.get("commence_time", ""),
                "game_status": _normalize_event_status(event),
            }
        ],
    )

    cache.clear_game_props(event_id)
    inserted = 0
    skipped_missing_player_or_line = 0
    skipped_duplicate_market = 0
    skipped_duplicate_event = 0
    seen_event_props: set[tuple[str, str, str, float]] = set()

    for bookmaker in odds_payload.get("bookmakers", []):
        bookmaker_name = str(
            bookmaker.get("title")
            or bookmaker.get("key")
            or ""
        )

        for market in bookmaker.get("markets", []):
            market_key = str(market.get("key", ""))
            seen_market_rows: set[tuple[str, float]] = set()

            for outcome in market.get("outcomes", []):
                player_name = str(
                    outcome.get("description")
                    or outcome.get("player")
                    or ""
                )
                point = outcome.get("point")

                if not player_name or not isinstance(point, (int, float)):
                    skipped_missing_player_or_line += 1
                    continue

                market_row_key = (player_name, float(point))
                if market_row_key in seen_market_rows:
                    skipped_duplicate_market += 1
                    continue
                seen_market_rows.add(market_row_key)

                event_prop_key = (
                    bookmaker_name.strip().lower(),
                    market_key.strip().lower(),
                    player_name.strip().lower(),
                    float(point),
                )
                if event_prop_key in seen_event_props:
                    skipped_duplicate_event += 1
                    continue
                seen_event_props.add(event_prop_key)

                snapshot_key = (
                    bookmaker_name.strip().lower(),
                    market_key.strip().lower(),
                    player_name.strip().lower(),
                )
                previous = previous_snapshots.get(snapshot_key)
                current_line = float(point)
                opening_line = current_line
                line_updated_at = updated_at
                if previous is not None:
                    prior_opening = previous.get("opening_line")
                    prior_current = previous.get("current_line")
                    if isinstance(prior_opening, (int, float)):
                        opening_line = float(prior_opening)
                    elif isinstance(previous.get("line"), (int, float)):
                        opening_line = float(previous["line"])

                    if isinstance(prior_current, (int, float)) and float(prior_current) == current_line:
                        prior_moved_at = str(previous.get("line_updated_at") or "").strip()
                        if prior_moved_at:
                            line_updated_at = prior_moved_at

                matching_outcomes = [
                    candidate
                    for candidate in market.get("outcomes", [])
                    if (
                        candidate.get("description")
                        == outcome.get("description")
                        and candidate.get("point") == point
                    )
                ]

                over_odds = _find_price(matching_outcomes, "Over")
                under_odds = _find_price(matching_outcomes, "Under")
                prediction, confidence = calculate_prediction(
                    over_odds,
                    under_odds,
                )

                cache.insert_prop(
                    game_id=event_id,
                    player_name=player_name,
                    prop_type=market_key,
                    line=current_line,
                    opening_line=opening_line,
                    current_line=current_line,
                    line_updated_at=line_updated_at,
                    over_odds=over_odds or -110,
                    under_odds=under_odds or -110,
                    bookmaker=bookmaker_name,
                    prediction=prediction,
                    confidence=confidence,
                    source_player_id=str(
                        outcome.get("player_id")
                        or outcome.get("participant_id")
                        or outcome.get("id")
                        or ""
                    ),
                    updated_at=updated_at,
                )
                inserted += 1

    logger.info(
        "prop_processor event_id=%s sport=%s inserted=%s skipped_missing=%s skipped_dup_market=%s skipped_dup_event=%s",
        event_id,
        sport_key,
        inserted,
        skipped_missing_player_or_line,
        skipped_duplicate_market,
        skipped_duplicate_event,
    )

    return inserted
