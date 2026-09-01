import base64
import json

from services.security_event_service import stable_actor_identity


def _token(payload: dict[str, object]) -> str:
    encoded = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode()
    return f"header.{encoded.rstrip('=')}.signature"


def test_bearer_activity_uses_stable_supabase_user_id() -> None:
    assert (
        stable_actor_identity(
            f"Bearer {_token({'sub': 'user-123', 'exp': 9999999999})}",
            "127.0.0.1",
        )
        == "user-123"
    )


def test_anonymous_activity_uses_network_fallback() -> None:
    assert stable_actor_identity("", "203.0.113.8") == "203.0.113.8"
