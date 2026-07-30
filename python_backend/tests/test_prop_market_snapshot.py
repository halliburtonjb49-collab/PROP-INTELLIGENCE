from services.prop_service import market_snapshot


def test_market_snapshot_uses_median_and_distinct_books() -> None:
    snapshot = market_snapshot(
        [
            {
                "line": 24.5,
                "bookmaker": "Book A",
                "over_odds": -110.0,
                "under_odds": -105.0,
            },
            {
                "line": 23.5,
                "bookmaker": "Book B",
                "over_odds": 105.0,
                "under_odds": -115.0,
            },
            {
                "line": 25.5,
                "bookmaker": "Book C",
                "over_odds": -120.0,
                "under_odds": 110.0,
            },
        ],
        24.5,
    )

    assert snapshot["origin_line"] == 24.5
    assert snapshot["book_count"] == 3
    assert snapshot["best_over"] == (105.0, "Book B")
    assert snapshot["best_under"] == (110.0, "Book C")
