from models.sync_diagnostic import TicketSyncDiagnostic
from services import sync_diagnostic_service


def test_sync_report_hashes_request_id_and_excludes_ticket_content(monkeypatch) -> None:
    captured = {}
    monkeypatch.setattr(
        sync_diagnostic_service,
        "record_security_event",
        lambda event_type, **kwargs: captured.update(event_type=event_type, **kwargs),
    )
    result = sync_diagnostic_service.record_ticket_sync_diagnostic(
        TicketSyncDiagnostic(
            phase="error", error_category="network", attempts=3,
            client_request_id="private-retry-id", platform="web",
        ),
        user_id="user-1",
    )

    assert result["diagnosticId"].startswith("SYNC-")
    assert captured["event_type"] == "ticket_sync_diagnostic"
    assert captured["identity"] == "user-1"
    assert captured["outcome"] == "network"
    assert captured["metadata"]["requestFingerprint"] != "private-retry-id"
    assert "stake" not in captured["metadata"]
    assert "legs" not in captured["metadata"]


def test_summary_degrades_without_database(monkeypatch) -> None:
    monkeypatch.setattr(sync_diagnostic_service, "database_is_configured", lambda: False)
    assert sync_diagnostic_service.ticket_sync_diagnostic_summary() == {
        "databaseConfigured": False,
        "last24Hours": 0,
        "last7Days": 0,
        "categories": [],
    }
