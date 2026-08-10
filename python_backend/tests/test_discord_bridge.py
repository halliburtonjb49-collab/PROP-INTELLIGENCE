from fastapi.testclient import TestClient

import main
from routers import discord_chat
from services.api_auth_service import require_user_id
from services.discord_bridge_service import DiscordBridge, trusted_chat_username


def test_bridge_requires_token_and_numeric_channel_id(monkeypatch) -> None:
    bridge = DiscordBridge()
    monkeypatch.setenv("DISCORD_BOT_TOKEN", "rotated-token")
    monkeypatch.setenv("DISCORD_CHANNEL_ID", "123456789")

    assert bridge.configured is True
    assert bridge.health() == {
        "configured": True,
        "connected": False,
        "channelConfigured": True,
    }

    monkeypatch.setenv("DISCORD_CHANNEL_ID", "https://discord.gg/invite")
    assert bridge.configured is False


def test_trusted_username_falls_back_without_database(monkeypatch) -> None:
    monkeypatch.setattr(
        "services.discord_bridge_service.database_is_configured",
        lambda: False,
    )

    assert trusted_chat_username("12345678-abcd-0000-0000-000000000000") == (
        "member_12345678"
    )


def test_authenticated_general_message_is_mirrored(monkeypatch) -> None:
    captured = {}

    async def fake_send(*, username: str, text: str) -> str:
        captured.update(username=username, text=text)
        return "discord-message-1"

    main.app.dependency_overrides[require_user_id] = lambda: "user-1"
    monkeypatch.setattr(discord_chat.discord_bridge, "send", fake_send)
    monkeypatch.setattr(discord_chat, "trusted_chat_username", lambda _: "trusted_user")
    try:
        response = TestClient(main.app).post(
            "/api/realtime/discord/messages",
            json={"text": "Research this prop", "roomId": "general"},
        )
    finally:
        main.app.dependency_overrides.pop(require_user_id, None)

    assert response.status_code == 200
    assert response.json() == {
        "status": "sent",
        "messageId": "discord-message-1",
    }
    assert captured == {"username": "trusted_user", "text": "Research this prop"}


def test_non_general_room_is_not_mirrored() -> None:
    main.app.dependency_overrides[require_user_id] = lambda: "user-1"
    try:
        response = TestClient(main.app).post(
            "/api/realtime/discord/messages",
            json={"text": "private content", "roomId": "pro-room"},
        )
    finally:
        main.app.dependency_overrides.pop(require_user_id, None)

    assert response.status_code == 400