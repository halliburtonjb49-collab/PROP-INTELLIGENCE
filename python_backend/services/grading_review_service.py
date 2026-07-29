"""Owner review queue for unsettled tickets and potentially unsafe grading."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from services.slip_service import get_slips


def _parse_time(value: str) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed
    except (AttributeError, ValueError):
        return None


def grading_review_queue(*, now: datetime | None = None) -> dict[str, object]:
    current = now or datetime.now(timezone.utc)
    items: list[dict[str, object]] = []
    for slip in get_slips():
        for leg in slip.legs:
            reasons: list[str] = []
            start = _parse_time(leg.game_start_time)
            if (
                leg.result_status == "pending"
                and start is not None
                and start < current - timedelta(hours=6)
            ):
                reasons.append("pending_more_than_6_hours_after_start")
            if leg.game_completed and leg.result_status == "pending":
                reasons.append("completed_game_has_pending_grade")
            if (
                leg.result_status in {"won", "lost", "push"}
                and not leg.result_verified
            ):
                reasons.append("grade_not_authoritatively_verified")
            if not reasons:
                continue
            items.append({
                "slipId": slip.id,
                "slipStatus": slip.status,
                "propId": leg.prop_id,
                "player": leg.player,
                "sport": leg.sport,
                "market": leg.market,
                "line": leg.line,
                "side": leg.side,
                "resultValue": leg.result_value,
                "resultStatus": leg.result_status,
                "resultSource": leg.result_source,
                "gameStartTime": leg.game_start_time,
                "reasons": reasons,
            })
    unsettled = sum(item["resultStatus"] == "pending" for item in items)
    questionable = len(items) - unsettled
    return {
        "generatedAt": current.isoformat(),
        "unsettledCount": unsettled,
        "questionableCount": questionable,
        "count": len(items),
        "items": items,
    }
