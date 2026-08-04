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
    monkeypatch.setattr(
        sportmonks_cricket,
        "_get",
        lambda *a, **k: {"data": [{"id": 1, "odds": [{"market": "Match Winner"}]}]},
    )
    result = sportmonks_cricket.probe_cricket_odds_shape()
    assert result["status"] == "ok"
    assert result["fixtureCount"] == 1
    assert result["hasOdds"] is True


def test_cricketdata_health_check_not_configured(monkeypatch):
    monkeypatch.setattr(sportmonks_cricket, "CRICKETDATA_API_KEY", "")
    assert sportmonks_cricket.cricketdata_health_check() == {"status": "not_configured"}
