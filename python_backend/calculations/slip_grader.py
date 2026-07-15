from typing import Literal

LegStatus = Literal["pending", "won", "lost", "push"]


def grade_leg(
    *,
    side: str,
    line: float,
    result_value: float | None,
) -> LegStatus:
    if result_value is None:
        return "pending"

    normalized_side = side.upper()

    if result_value == line:
        return "push"

    if normalized_side == "OVER":
        return "won" if result_value > line else "lost"

    if normalized_side == "UNDER":
        return "won" if result_value < line else "lost"

    return "pending"


def grade_slip_status(
    leg_statuses: list[str],
) -> str:
    if not leg_statuses:
        return "active"

    if any(status == "lost" for status in leg_statuses):
        return "lost"

    if all(status in {"won", "push"} for status in leg_statuses):
        return "won"

    return "active"
