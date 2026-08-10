from services import api_auth_service


def _user():
    return {
        "id": "member-id",
        "email": "member@example.com",
        "app_metadata": {"role": "user"},
    }


def test_owner_granted_pro_founder_bypasses_payment(monkeypatch):
    monkeypatch.setattr(api_auth_service, "_supabase_user", lambda _token: _user())
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_profile",
        lambda _token, _user_id: {
            "subscription_tier": "free",
            "is_premium": False,
            "assigned_member_role": "pro_founder",
            "founder_number": 7,
        },
    )

    membership = api_auth_service.resolve_membership(
        authorization="Bearer valid-token"
    )

    assert membership.has_pro_access is True
    assert membership.role == "pro_founder"


def test_core_grant_does_not_downgrade_paid_pro(monkeypatch):
    monkeypatch.setattr(api_auth_service, "_supabase_user", lambda _token: _user())
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_profile",
        lambda _token, _user_id: {
            "subscription_tier": "pro",
            "is_premium": True,
            "assigned_member_role": "core",
        },
    )

    membership = api_auth_service.resolve_membership(
        authorization="Bearer valid-token"
    )

    assert membership.has_pro_access is True
    assert membership.subscription_tier == "pro"
