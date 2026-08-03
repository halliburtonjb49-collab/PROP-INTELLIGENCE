from services.prop_catalog_snapshot_service import _decode_payload, _encode_payload


def test_catalog_snapshot_round_trip_preserves_rows() -> None:
    rows = [
        {"id": "prop-1", "player": "Player One", "line": 5.5},
        {"id": "prop-2", "player": "Player Two", "line": 7.0},
    ]

    assert _decode_payload(_encode_payload(rows)) == rows


def test_catalog_snapshot_rejects_empty_or_invalid_payload() -> None:
    assert _decode_payload(b"") == []
