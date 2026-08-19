import importlib.util
from pathlib import Path

import dotenv


def test_shared_config_import_does_not_require_odds_credentials(
    monkeypatch,
) -> None:
    monkeypatch.delenv("ODDS_API_KEY", raising=False)
    monkeypatch.delenv("API_SPORTS_KEY", raising=False)
    monkeypatch.setattr(dotenv, "load_dotenv", lambda *_args, **_kwargs: False)

    path = Path(__file__).resolve().parents[1] / "config.py"
    spec = importlib.util.spec_from_file_location("headshot_config_test", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    assert module.ODDS_API_KEY == ""
    assert module.API_SPORTS_KEY == ""
    assert module.ESPN_HEADSHOT_MAP_PATH
