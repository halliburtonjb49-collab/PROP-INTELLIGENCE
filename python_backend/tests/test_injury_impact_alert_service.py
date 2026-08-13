from datetime import datetime, timezone

import main

from services.injury_impact_alert_service import (
    build_injury_impact_snapshot,
    detect_injury_impact_changes,
)


def prop(
    *,
    site: str = "PRIZEPICKS",
    injury: str = "no injury reported",
    lineup: str = "confirmed",
    role: str = "UNKNOWN",
    usage: float | None = None,
) -> dict[str, object]:
    return {
        "eventId": "game-1",
        "canonicalPlayerId": "player-1",
        "player": "Alex Guard",
        "sport": "NBA",
        "matchup": "AWAY @ HOME",
        "sportsbook": site,
        "displayMarket": "Points",
        "injuryStatus": injury,
        "lineupStatus": lineup,
        "roleChange": role,
        "usageMultiplier": usage,
    }


def test_first_snapshot_is_a_baseline_not_a_notification() -> None:
    current = build_injury_impact_snapshot([prop(injury="questionable")])
    assert detect_injury_impact_changes(current, current) == []


def test_healthy_to_out_emits_one_critical_player_event_across_sites() -> None:
    previous = build_injury_impact_snapshot(
        [prop(), prop(site="UNDERDOG")]
    )
    current = build_injury_impact_snapshot(
        [prop(injury="out"), prop(site="UNDERDOG", injury="out")]
    )
    events = detect_injury_impact_changes(
        previous,
        current,
        occurred_at=datetime(2026, 8, 9, 15, tzinfo=timezone.utc),
    )
    assert len(events) == 1
    assert events[0]["level"] == "CRITICAL"
    assert events[0]["player"] == "Alex Guard"
    assert events[0]["sites"] == ["PRIZEPICKS", "UNDERDOG"]
    assert events[0]["occurredAt"] == "2026-08-09T15:00:00Z"


def test_unchanged_refresh_is_deduplicated() -> None:
    previous = build_injury_impact_snapshot([prop(injury="questionable")])
    current = build_injury_impact_snapshot([prop(injury="questionable")])
    assert detect_injury_impact_changes(previous, current) == []


def test_material_role_change_emits_watch_and_recovery_emits_cleared() -> None:
    healthy = build_injury_impact_snapshot([prop()])
    expanded = build_injury_impact_snapshot([prop(role="EXPANDED", usage=1.08)])
    watch = detect_injury_impact_changes(healthy, expanded)
    assert len(watch) == 1
    assert watch[0]["level"] == "WATCH"

    cleared = detect_injury_impact_changes(expanded, healthy)
    assert len(cleared) == 1
    assert cleared[0]["level"] == "CLEARED"


def test_sub_two_percent_factor_does_not_create_impact() -> None:
    snapshot = build_injury_impact_snapshot([prop(usage=1.019)])
    assert next(iter(snapshot.values()))["level"] == "NONE"

def test_catalog_refresh_broadcasts_detected_change_once(monkeypatch) -> None:
    calls: list[tuple[dict[str, object], str]] = []
    alert = {
        "eventId": "event-change-1",
        "occurredAt": "2026-08-09T15:00:00Z",
        "level": "CRITICAL",
    }
    monkeypatch.setattr(main, "_invalidate_prop_catalog", lambda: None)
    monkeypatch.setattr(
        main,
        "_rebuild_prop_catalog_from_local",
        lambda **_kwargs: [prop()],
    )
    monkeypatch.setattr(main, "evaluate_injury_impact_changes", lambda _: [alert])
    monkeypatch.setattr(
        main.realtime_hub,
        "broadcast_from_thread",
        lambda event, channel: calls.append((event, channel)),
    )

    main._refresh_prop_catalog_now()

    assert len(calls) == 1
    assert calls[0][1] == "alerts"
    assert calls[0][0]["type"] == "injury.impact.changed"
    assert calls[0][0]["data"] == alert
