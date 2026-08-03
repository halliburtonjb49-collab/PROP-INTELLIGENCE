from services.smartstake_backtest_service import manifest_megabytes, monthly_files


def test_monthly_files_selects_only_requested_parquet() -> None:
    entries = [
        {"path": "mon=2026-05/part-001.parquet", "size": 20},
        {"path": "mon=2026-05/part-000.parquet", "size": 10},
        {"path": "mon=2026-06/part-000.parquet", "size": 30},
        {"path": "README.md", "size": 5},
    ]
    assert monthly_files(entries, "2026-05") == [
        {"path": "mon=2026-05/part-000.parquet", "size": 10},
        {"path": "mon=2026-05/part-001.parquet", "size": 20},
    ]


def test_manifest_megabytes() -> None:
    assert manifest_megabytes([{"size": 1_500_000}, {"size": 500_000}]) == 2.0
