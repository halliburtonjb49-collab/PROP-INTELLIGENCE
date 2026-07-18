from services.sync_service import prioritize_events


def test_events_are_prioritized_by_start_time_with_invalid_rows_last() -> None:
    events = [
        {"id": "late", "commence_time": "2026-07-18T02:00:00Z"},
        {"id": "missing"},
        {"id": "soon", "commence_time": "2026-07-17T20:00:00Z"},
        {"id": "middle", "commence_time": "2026-07-17T23:00:00Z"},
    ]
    assert [event["id"] for event in prioritize_events(events)] == [
        "soon", "middle", "late", "missing",
    ]


def test_equal_start_times_have_stable_id_order() -> None:
    events = [
        {"id": "b", "commence_time": "2026-07-17T20:00:00Z"},
        {"id": "a", "commence_time": "2026-07-17T20:00:00Z"},
    ]
    assert [event["id"] for event in prioritize_events(events)] == ["a", "b"]
