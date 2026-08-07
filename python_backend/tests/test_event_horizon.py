from datetime import datetime, timedelta, timezone

from services.sync_service import prioritize_events, within_horizon


def _event(event_id: str, *, days_ahead: float | None) -> dict[str, object]:
    if days_ahead is None:
        return {"id": event_id}
    start = datetime.now(timezone.utc) + timedelta(days=days_ahead)
    return {"id": event_id, "commence_time": start.isoformat().replace("+00:00", "Z")}


def test_a_distant_game_is_not_worth_a_credit() -> None:
    # The defect behind nine empty sports: in August the NFL lists its whole
    # season, and pricing December games exhausts the keys before the sports
    # later in the cycle are reached.
    kept, dropped = within_horizon(
        [_event("tonight", days_ahead=0.2), _event("december", days_ahead=120)],
        days=7,
    )

    assert [event["id"] for event in kept] == ["tonight"]
    assert dropped == 1


def test_the_whole_upcoming_week_survives() -> None:
    events = [_event(str(day), days_ahead=day) for day in range(7)]
    kept, dropped = within_horizon(events, days=7)

    assert len(kept) == 7
    assert dropped == 0


def test_an_undated_event_is_kept_rather_than_guessed_at() -> None:
    """We cannot show it is far away, so dropping it is the worse mistake."""

    kept, dropped = within_horizon([_event("no-time", days_ahead=None)], days=7)

    assert [event["id"] for event in kept] == ["no-time"]
    assert dropped == 0


def test_the_bound_can_be_turned_off() -> None:
    events = [_event("a", days_ahead=0.1), _event("b", days_ahead=400)]

    assert within_horizon(events, days=0) == (events, 0)


def test_nothing_is_dropped_silently() -> None:
    # A sport showing few events must be able to say it was bounded rather
    # than look naturally small.
    _, dropped = within_horizon(
        [_event(str(index), days_ahead=30 + index) for index in range(9)],
        days=7,
    )

    assert dropped == 9


def test_the_nearest_slate_is_still_served_first() -> None:
    # Ordering and bounding are separate jobs; the bound must not disturb it.
    events = prioritize_events(
        [
            _event("late", days_ahead=5),
            _event("soon", days_ahead=1),
            _event("season", days_ahead=90),
        ]
    )
    kept, dropped = within_horizon(events, days=7)

    assert [event["id"] for event in kept] == ["soon", "late"]
    assert dropped == 1


def test_an_ordinary_daily_slate_is_untouched() -> None:
    # MLB returns roughly one day of games and already yields 206 props per
    # event. The bound must cost it nothing.
    events = [_event(str(index), days_ahead=0.1) for index in range(15)]
    kept, dropped = within_horizon(events, days=7)

    assert len(kept) == 15
    assert dropped == 0
