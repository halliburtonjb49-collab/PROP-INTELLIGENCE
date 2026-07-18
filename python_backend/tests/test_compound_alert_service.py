from services.compound_alert_service import alert_fingerprint


def test_alert_fingerprint_is_stable_and_snapshot_specific() -> None:
    first = alert_fingerprint("alert-1", {"line": 7, "status": "OUT"})
    reordered = alert_fingerprint("alert-1", {"status": "OUT", "line": 7})
    changed = alert_fingerprint("alert-1", {"line": 8, "status": "OUT"})
    assert first == reordered
    assert first != changed
