from services import prop_catalog_snapshot_service as snapshots


def test_props_newer_than_the_snapshot_are_behind(monkeypatch):
    monkeypatch.setattr(
        snapshots,
        "catalog_snapshot_metadata",
        lambda: {"exists": True, "dataUpdatedAt": "2026-08-06T17:05:19+00:00"},
    )
    rows = [{"lastUpdatedUtc": "2026-08-06T19:39:04+00:00"}]
    assert snapshots.snapshot_is_behind(rows) is True


def test_a_current_snapshot_is_not_behind(monkeypatch):
    monkeypatch.setattr(
        snapshots,
        "catalog_snapshot_metadata",
        lambda: {"exists": True, "dataUpdatedAt": "2026-08-06T19:39:04+00:00"},
    )
    rows = [{"lastUpdatedUtc": "2026-08-06T19:39:04+00:00"}]
    assert snapshots.snapshot_is_behind(rows) is False


def test_a_missing_snapshot_always_counts_as_behind(monkeypatch):
    monkeypatch.setattr(
        snapshots, "catalog_snapshot_metadata", lambda: {"exists": False}
    )
    assert snapshots.snapshot_is_behind([{"lastUpdatedUtc": "2026-08-06T10:00:00Z"}]) is True


def test_older_props_never_overwrite_a_newer_snapshot(monkeypatch):
    # A lagging instance must not push the stored catalog backwards.
    monkeypatch.setattr(
        snapshots,
        "catalog_snapshot_metadata",
        lambda: {"exists": True, "dataUpdatedAt": "2026-08-06T19:39:04+00:00"},
    )
    rows = [{"lastUpdatedUtc": "2026-08-06T17:05:19+00:00"}]
    assert snapshots.snapshot_is_behind(rows) is False


def test_nothing_to_compare_is_not_behind(monkeypatch):
    assert snapshots.snapshot_is_behind([]) is False
