from providers import sportmonks_cricket


def test_probe_returns_not_configured_when_key_missing(monkeypatch):
    monkeypatch.setattr(sportmonks_cricket, "SPORTMONKS_CRICKET_API_KEY", "")
    result = sportmonks_cricket.probe_cricket_odds_shape()
    assert result == {"status": "not_configured"}


def test_probe_reports_error_instead_of_raising(monkeypatch):
    monkeypatch.setattr(sportmonks_cricket, "SPORTMONKS_CRICKET_API_KEY", "test-key")

    def _boom(*_args, **_kwargs):
        raise RuntimeError("boom")

    monkeypatch.setattr(sportmonks_cricket, "_get", _boom)
    result = sportmonks_cricket.probe_cricket_odds_shape()
    assert result["status"] == "error"
    assert "boom" in result["error"]


def test_probe_reports_no_fixtures(monkeypatch):
    monkeypatch.setattr(sportmonks_cricket, "SPORTMONKS_CRICKET_API_KEY", "test-key")
    monkeypatch.setattr(
        sportmonks_cricket, "_get", lambda *a, **k: {"data": [], "meta": {}}
    )
    result = sportmonks_cricket.probe_cricket_odds_shape()
    assert result["status"] == "no_fixtures"


def test_probe_reports_ok_with_fixture_and_odds(monkeypatch):
    monkeypatch.setattr(sportmonks_cricket, "SPORTMONKS_CRICKET_API_KEY", "test-key")

    def _get(path, _params):
        if path.startswith("odds/fixture/"):
            return {"data": [{"market": "Match Winner"}]}
        return {"data": [{"id": 1, "odds": [{"market": "Match Winner"}]}]}

    monkeypatch.setattr(sportmonks_cricket, "_get", _get)
    result = sportmonks_cricket.probe_cricket_odds_shape()
    assert result["status"] == "ok"
    assert result["fixtureCount"] == 1
    assert result["hasIncludedOdds"] is True
    assert result["hasDedicatedOdds"] is True
    assert result["dedicatedOddsError"] is None


def test_probe_falls_back_when_dedicated_odds_endpoint_errors(monkeypatch):
    monkeypatch.setattr(sportmonks_cricket, "SPORTMONKS_CRICKET_API_KEY", "test-key")

    def _get(path, _params):
        if path.startswith("odds/fixture/"):
            raise RuntimeError("404")
        return {"data": [{"id": 1, "odds": None}]}

    monkeypatch.setattr(sportmonks_cricket, "_get", _get)
    result = sportmonks_cricket.probe_cricket_odds_shape()
    assert result["status"] == "ok"
    assert result["hasIncludedOdds"] is False
    assert result["hasDedicatedOdds"] is False
    assert result["dedicatedOddsError"] == "404"


def test_cricketdata_health_check_not_configured(monkeypatch):
    monkeypatch.setattr(sportmonks_cricket, "CRICKETDATA_API_KEY", "")
    assert sportmonks_cricket.cricketdata_health_check() == {"status": "not_configured"}
