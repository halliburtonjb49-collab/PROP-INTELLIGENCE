from datetime import datetime, timezone
from typing import Any

from models.prop_builder import PropBuilderLeg
from models.prop_line_movement import (
    PropLineMovementResponse,
)


def _normalize(value: str) -> str:
    return " ".join(value.strip().lower().split())


def _safe_float_or_none(
    value: Any,
) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _safe_int_or_none(
    value: Any,
) -> int | None:
    try:
        if value is None:
            return None
        return int(float(value))
    except (TypeError, ValueError):
        return None


def _row_value(
    row: Any,
    key: str,
    default: Any = None,
) -> Any:
    if isinstance(row, dict):
        return row.get(key, default)
    try:
        return row[key]
    except (KeyError, TypeError, IndexError):
        return getattr(row, key, default)


def _find_matching_prop(
    *,
    leg: PropBuilderLeg,
    prop_rows: list[Any],
) -> Any | None:
    for row in prop_rows:
        row_prop_id = str(_row_value(row, "id", "")).strip()
        if (
            leg.prop_id
            and row_prop_id
            and row_prop_id == leg.prop_id
        ):
            return row

    for row in prop_rows:
        same_player = (
            _normalize(str(_row_value(row, "player", "")))
            == _normalize(leg.player)
        )
        same_market = (
            _normalize(str(_row_value(row, "market", "")))
            == _normalize(leg.market)
        )
        same_site = (
            _normalize(
                str(
                    _row_value(
                        row,
                        "prop_site",
                        _row_value(row, "sportsbook", ""),
                    )
                )
            )
            == _normalize(leg.prop_site)
        )
        same_event = (
            not leg.event_id
            or str(_row_value(row, "event_id", "")) == leg.event_id
        )
        if (
            same_player
            and same_market
            and same_site
            and same_event
        ):
            return row

    return None


def _movement_status(
    *,
    side: str,
    original_line: float | None,
    current_line: float | None,
    original_odds: int | None,
    current_odds: int | None,
) -> str:
    if current_line is None:
        return "UNAVAILABLE"

    normalized_side = side.strip().upper()
    line_changed = (
        original_line is not None
        and current_line != original_line
    )
    odds_changed = (
        original_odds is not None
        and current_odds is not None
        and current_odds != original_odds
    )

    if not line_changed and not odds_changed:
        return "UNCHANGED"

    if (
        original_line is not None
        and current_line != original_line
    ):
        if normalized_side == "OVER":
            return "BETTER" if current_line < original_line else "WORSE"
        if normalized_side == "UNDER":
            return "BETTER" if current_line > original_line else "WORSE"

    if (
        original_odds is not None
        and current_odds is not None
        and current_odds != original_odds
    ):
        return "BETTER" if current_odds > original_odds else "WORSE"

    return "MOVED"


def check_prop_line_movement(
    *,
    legs: list[PropBuilderLeg],
    prop_rows: list[Any],
) -> PropLineMovementResponse:
    checked_at = datetime.now(timezone.utc).isoformat()
    updated_legs: list[PropBuilderLeg] = []
    changed_count = 0
    unavailable_count = 0

    for input_leg in legs:
        leg = input_leg.model_copy(deep=True)
        matching_row = _find_matching_prop(
            leg=leg,
            prop_rows=prop_rows,
        )

        if matching_row is None:
            leg.movement_status = "UNAVAILABLE"
            leg.last_line_check = checked_at
            unavailable_count += 1
            updated_legs.append(leg)
            continue

        current_line = _safe_float_or_none(
            _row_value(
                matching_row,
                "line",
                None,
            )
        )
        current_odds = _safe_int_or_none(
            _row_value(
                matching_row,
                "odds",
                None,
            )
        )
        if current_odds is None:
            if leg.side.strip().upper() == "UNDER":
                current_odds = _safe_int_or_none(
                    _row_value(
                        matching_row,
                        "under_odds",
                        None,
                    )
                )
            else:
                current_odds = _safe_int_or_none(
                    _row_value(
                        matching_row,
                        "over_odds",
                        None,
                    )
                )

        original_line = (
            leg.original_line
            if leg.original_line is not None
            else leg.line
        )
        original_odds = (
            leg.original_odds
            if leg.original_odds is not None
            else leg.odds
        )

        leg.original_line = original_line
        leg.original_odds = original_odds
        leg.current_line = current_line
        leg.current_odds = current_odds
        leg.line_change = (
            round(current_line - original_line, 2)
            if (
                current_line is not None
                and original_line is not None
            )
            else 0
        )
        leg.odds_change = (
            current_odds - original_odds
            if (
                current_odds is not None
                and original_odds is not None
            )
            else 0
        )
        leg.movement_status = _movement_status(
            side=leg.side,
            original_line=original_line,
            current_line=current_line,
            original_odds=original_odds,
            current_odds=current_odds,
        )
        leg.last_line_check = checked_at

        if leg.movement_status not in {
            "UNCHANGED",
            "UNAVAILABLE",
        }:
            changed_count += 1

        updated_legs.append(leg)

    return PropLineMovementResponse(
        legs=updated_legs,
        checked_count=len(updated_legs),
        changed_count=changed_count,
        unavailable_count=unavailable_count,
    )
