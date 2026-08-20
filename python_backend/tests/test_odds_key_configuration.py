import os
import subprocess
import sys
from pathlib import Path

import pytest

from services import odds_service


def test_a_missing_odds_key_names_itself_instead_of_failing_as_a_401(
    monkeypatch,
):
    """An absent credential is not a rejected one.

    The unset key was sent as an empty string, so the provider answered 401
    and rotation read it as a deactivated key: it marked a key that does not
    exist dead, had nothing to fail over to, and surfaced an authentication
    error. The board went empty for a reason no log line named.
    """

    monkeypatch.setattr(odds_service, "_ODDS_API_KEYS", [])

    def _no_request(*_args, **_kwargs):
        raise AssertionError("a request must not be attempted without a key")

    monkeypatch.setattr(odds_service, "_http_session", _no_request)

    with pytest.raises(RuntimeError, match="ODDS_API_KEY is not configured"):
        odds_service.fetch_events("baseball_mlb")


def test_a_configured_key_still_reaches_the_provider(monkeypatch):
    calls: list[dict] = []

    class _Response:
        status_code = 200
        headers: dict[str, str] = {}

        @staticmethod
        def json():
            return [{"id": "evt"}]

        @staticmethod
        def raise_for_status():
            return None

    class _Session:
        @staticmethod
        def get(url, params=None, timeout=None):
            calls.append({"url": url, "params": params})
            return _Response()

    monkeypatch.setattr(odds_service, "_ODDS_API_KEYS", ["live-key"])
    monkeypatch.setattr(odds_service, "_http_session", lambda: _Session())
    monkeypatch.setattr(odds_service, "record_quota_headers", lambda _h: None)

    assert odds_service.fetch_events("baseball_mlb") == [{"id": "evt"}]
    assert calls[0]["params"]["apiKey"] == "live-key"


def test_the_headshot_sync_imports_without_any_odds_credential():
    """A headshot-only job must not require an odds credential.

    The ESPN headshot cron once failed at import because the shared config
    module demanded ODDS_API_KEY. The guard now lives in the odds service, so
    this proves the coupling has not crept back through another import.
    """

    backend_root = Path(__file__).resolve().parents[1]
    # Strip only the odds credentials. Emptying the environment outright
    # breaks Windows socket initialisation and would test the harness
    # rather than the import.
    environment = {
        key: value
        for key, value in os.environ.items()
        if key not in {"ODDS_API_KEY", "ODDS_API_KEY_SECONDARY"}
    }
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            "import sys; sys.path.insert(0, '.');"
            " import config;"
            " from services.espn_headshot_service import"
            " refresh_espn_headshot_map;"
            " print('ok')",
        ],
        cwd=backend_root,
        capture_output=True,
        text=True,
        env=environment,
    )

    assert result.returncode == 0, result.stderr[-800:]
    assert "ok" in result.stdout
