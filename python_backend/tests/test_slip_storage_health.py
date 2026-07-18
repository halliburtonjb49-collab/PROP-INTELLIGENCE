from services import slip_service


def test_storage_health_initializes_writable_database(tmp_path, monkeypatch) -> None:
    path = tmp_path / "nested" / "tickets.db"
    monkeypatch.setattr(slip_service, "DATABASE_PATH", path)
    monkeypatch.setenv("SLIP_DATABASE_PATH", str(path))
    result = slip_service.slip_storage_health()
    assert result["status"] == "ok"
    assert result["mode"] == "persistent-disk"
    assert path.exists()
