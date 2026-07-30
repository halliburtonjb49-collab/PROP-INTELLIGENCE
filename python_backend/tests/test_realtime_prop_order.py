from routers.realtime import _non_soccer_first


def test_realtime_updates_place_provider_style_soccer_labels_last() -> None:
    rows = [
        {"id": "soccer", "sport": "soccer_usa_mls"},
        {"id": "nba", "sport": "NBA"},
        {"id": "mlb", "sport": "MLB"},
    ]

    assert [row["id"] for row in _non_soccer_first(rows)] == [
        "nba",
        "mlb",
        "soccer",
    ]
