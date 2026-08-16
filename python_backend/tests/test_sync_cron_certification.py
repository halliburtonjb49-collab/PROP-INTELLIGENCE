from scripts import sync_historical_daily, sync_pregame


def test_fast_lane_completion_is_not_full_sync_success() -> None:
    assert sync_pregame._full_sync_complete({
        "status": "complete",
        "coverageStatus": "running",
        "sportsGameOddsStatus": "pending",
        "postProcessingStatus": "pending",
    }) is False
    assert sync_pregame._full_sync_complete({
        "status": "complete",
        "coverageStatus": "complete",
        "sportsGameOddsStatus": "running",
        "postProcessingStatus": "pending",
    }) is False
    assert sync_pregame._full_sync_complete({
        "status": "complete",
        "coverageStatus": "complete",
        "sportsGameOddsStatus": "complete",
        "postProcessingStatus": "running",
    }) is False
    assert sync_pregame._full_sync_complete({
        "status": "complete",
        "coverageStatus": "complete",
        "sportsGameOddsStatus": "complete",
        "postProcessingStatus": "complete",
    }) is True
    assert sync_pregame._full_sync_complete({
        "status": "complete",
        "coverageStatus": "complete",
        "sportsGameOddsStatus": "partial",
        "postProcessingStatus": "complete",
    }) is True


def test_historical_cron_fails_when_any_mlb_chunk_failed() -> None:
    assert sync_historical_daily._coordinator_exit_code([], 0) == 0
    assert sync_historical_daily._coordinator_exit_code(
        [{"startDate": "2026-08-09", "error": "exit_status_1"}],
        0,
    ) == 1
    assert sync_historical_daily._coordinator_exit_code([], 1) == 1
