import base64
import json

from services import api_auth_service


def _unsigned_token(payload: dict[str, object]) -> str:
    encoded = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    return f"header.{encoded}.signature"


def test_verified_owner_email_has_admin_api_access(monkeypatch):
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_user",
        lambda _token: {
            "id": "owner-id",
            "email": "HalliburtonJB49@Gmail.com",
            "app_metadata": {},
            "user_metadata": {},
        },
    )

    assert api_auth_service.require_admin(authorization="Bearer valid-token") == "owner-id"


def test_verified_owner_user_id_has_owner_access(monkeypatch):
    owner_id = "84a76503-f704-46b6-be87-760ea8c9f2f5"
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_user",
        lambda _token: {
            "id": owner_id,
            "email": "changed@example.com",
            "app_metadata": {"role": "user"},
            "user_metadata": {},
        },
    )

    assert api_auth_service.require_owner(
        authorization="Bearer valid-token"
    ) == owner_id


def test_regular_verified_email_does_not_gain_admin_access(monkeypatch):
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_user",
        lambda _token: {
            "id": "user-id",
            "email": "user@example.com",
            "app_metadata": {},
            "user_metadata": {},
        },
    )

    try:
        api_auth_service.require_admin(authorization="Bearer valid-token")
    except Exception as exc:
        assert getattr(exc, "status_code", None) == 401
    else:
        raise AssertionError("Regular users must not receive administrator access")


def test_admin_role_does_not_gain_owner_only_access(monkeypatch):
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

    try:
        api_auth_service.require_owner(authorization="Bearer valid-token")
    except Exception as exc:
        assert getattr(exc, "status_code", None) == 403
    else:
        raise AssertionError("Administrators must not receive owner-only access")


def test_user_metadata_cannot_self_grant_owner_access(monkeypatch):
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_user",
        lambda _token: {
            "id": "regular-user-id",
            "email": "regular@example.com",
            "app_metadata": {"role": "user"},
            "user_metadata": {"role": "owner"},
        },
    )

    try:
        api_auth_service.require_owner(authorization="Bearer valid-token")
    except Exception as exc:
        assert getattr(exc, "status_code", None) == 403
    else:
        raise AssertionError("User metadata must not grant owner-only access")


def test_user_metadata_cannot_self_grant_admin_access(monkeypatch):
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_user",
        lambda _token: {
            "id": "regular-user-id",
            "email": "regular@example.com",
            "app_metadata": {"role": "user"},
            "user_metadata": {"role": "admin"},
        },
    )

    try:
        api_auth_service.require_admin(authorization="Bearer valid-token")
    except Exception as exc:
        assert getattr(exc, "status_code", None) == 401
    else:
        raise AssertionError("User metadata must not grant administrator access")


def test_validated_user_response_is_enriched_from_token_claims(monkeypatch):
    token = _unsigned_token({
        "email": "HalliburtonJB49@Gmail.com",
        "app_metadata": {"role": "owner"},
    })

    class _Response:
        status_code = 200

        @staticmethod
        def json():
            return {"id": "owner-id"}

    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "anon-key")
    monkeypatch.setattr(api_auth_service.requests, "get", lambda *args, **kwargs: _Response())

    user = api_auth_service._supabase_user(token)

    assert user is not None
    assert user["email"] == "HalliburtonJB49@Gmail.com"
    assert user["app_metadata"] == {"role": "owner"}
