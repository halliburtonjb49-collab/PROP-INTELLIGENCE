from fastapi.testclient import TestClient
import pytest

import main
from services import api_auth_service


OWNER_ONLY_REQUESTS = [
    ("GET", "/api/operations/readiness", None),
    ("GET", "/api/operations/acceptance", None),
    ("GET", "/api/operations/pipelines", None),
    ("GET", "/api/operations/provider-availability", None),
    ("GET", "/api/operations/provider-recovery", None),
    ("POST", "/api/operations/provider-recovery", {"targetSport": "MLB"}),
    ("GET", "/api/operations/command-center", None),
    ("GET", "/api/operations/model-audit", None),
    ("GET", "/api/operations/control-panel", None),
    ("GET", "/api/operations/billing-certification", None),
    ("GET", "/api/operations/grading-review", None),
    ("GET", "/api/operations/strikeout-controls", None),
    ("GET", "/api/operations/feedback", None),
    ("GET", "/api/admin/refresh-mlb-headshots/status", None),
    ("GET", "/api/admin/refresh-espn-headshots/status", None),
    ("GET", "/api/admin/refresh-gridiron-ice-history/status", None),
    ("GET", "/api/admin/refresh-golf-roster/status", None),
    ("GET", "/api/identity/map", None),
    ("GET", "/api/identity/unresolved", None),
    ("GET", "/api/identity/unresolved-grouped", None),
    ("GET", "/api/player-availability", None),
    (
        "POST",
        "/api/identity/map/bulk",
        {"providers": {}},
    ),
    (
        "POST",
        "/api/player-availability/bulk",
        {"players": {}},
    ),
]


@pytest.mark.parametrize(("method", "path", "payload"), OWNER_ONLY_REQUESTS)
def test_admin_account_is_blocked_from_owner_operations(
    monkeypatch,
    method: str,
    path: str,
    payload: dict[str, object] | None,
) -> None:
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_user",
        lambda _token: {
            "id": "admin-id",
            "email": "admin@example.com",
            "app_metadata": {"role": "admin"},
            "user_metadata": {},
        },
    )

    response = TestClient(main.app).request(
        method,
        path,
        headers={"Authorization": "Bearer admin-token"},
        json=payload,
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Owner access required"
