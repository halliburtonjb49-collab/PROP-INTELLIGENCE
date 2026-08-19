from scripts import sync_historical_daily, sync_pregame


class _Response:
    def __init__(self, status_code: int, payload: dict[str, object]) -> None:
        self.status_code = status_code
        self._payload = payload

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise AssertionError(f"unexpected terminal status {self.status_code}")

    def json(self) -> dict[str, object]:
        return self._payload


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


def test_pregame_sync_retries_transient_deploy_gateway_errors(
    monkeypatch,
) -> None:
    complete = {
        "status": "complete",
        "coverageStatus": "complete",
        "sportsGameOddsStatus": "complete",
        "postProcessingStatus": "complete",
    }
    responses = iter([_Response(502, {}), _Response(503, {}), _Response(200, complete)])
    monkeypatch.setenv("API_BASE_URL", "https://api.example.test")
    monkeypatch.setattr(sync_pregame.requests, "request", lambda *_args, **_kwargs: next(responses))
    monkeypatch.setattr(sync_pregame.time, "sleep", lambda _seconds: None)

    assert sync_pregame.run_live_api_sync() == complete
