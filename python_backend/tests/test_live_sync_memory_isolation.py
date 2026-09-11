from pathlib import Path

from services import sync_service


def test_live_sync_learning_is_disabled_by_default(monkeypatch) -> None:
    monkeypatch.delenv("LIVE_SYNC_LEARNING_ENABLED", raising=False)

    assert sync_service._live_learning_enabled() is False


def test_live_sync_learning_requires_explicit_opt_in(monkeypatch) -> None:
    monkeypatch.setenv("LIVE_SYNC_LEARNING_ENABLED", "true")

    assert sync_service._live_learning_enabled() is True


def test_production_blueprint_isolates_learning_from_live_worker() -> None:
    blueprint = Path("render.yaml").read_text(encoding="utf-8")

    assert "name: prop-intelligence-learning" in blueprint
    assert "LIVE_SYNC_LEARNING_ENABLED" in blueprint


def test_identity_reconcile_runs_from_backend_import_root() -> None:
    blueprint = Path("render.yaml").read_text(encoding="utf-8")

    assert (
        "startCommand: cd python_backend && python -m "
        "scripts.reconcile_identity_media"
    ) in blueprint
