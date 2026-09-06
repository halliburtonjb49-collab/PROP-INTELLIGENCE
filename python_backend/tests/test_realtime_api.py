import asyncio

from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from main import app
from routers import realtime


def _accept_test_token(monkeypatch) -> None:
    class _Membership:
        user_id = "user-1"
        has_core_access = True

    monkeypatch.setattr(
        realtime,
        "resolve_membership",
        lambda authorization: _Membership()
        if authorization == "Bearer valid"
        else (_ for _ in ()).throw(ValueError("invalid")),
    )


def test_props_channel_requires_authentication_and_pongs(monkeypatch) -> None:
    _accept_test_token(monkeypatch)
    client = TestClient(app)
    with client.websocket_connect("/api/realtime/ws?channels=props,unknown") as socket:
        assert socket.receive_json()["type"] == "authentication.required"
        socket.send_json({"type": "authenticate", "token": "valid"})
        ready = socket.receive_json()
        assert ready["type"] == "connection.ready"
        assert ready["version"] == 1
        assert ready["channels"] == ["props"]
        socket.send_text("ping")
        for _ in range(3):
            if socket.receive_json()["type"] == "pong":
                break
        else:
            raise AssertionError("WebSocket did not return pong")


def test_props_channel_rejects_account_without_core_entitlement(monkeypatch) -> None:
    class _FreeMembership:
        user_id = "free-user"
        has_core_access = False

    monkeypatch.setattr(
        realtime, "resolve_membership", lambda _authorization: _FreeMembership()
    )
    client = TestClient(app)
    with client.websocket_connect("/api/realtime/ws?channels=props") as socket:
        assert socket.receive_json()["type"] == "authentication.required"
        socket.send_json({"type": "authenticate", "token": "free"})
        try:
            socket.receive_json()
        except WebSocketDisconnect as exc:
            assert exc.code == 4401
        else:
            raise AssertionError("Free account unexpectedly received protected props")


def test_ticket_channel_requires_and_accepts_authentication(monkeypatch) -> None:
    _accept_test_token(monkeypatch)
    client = TestClient(app)
    with client.websocket_connect("/api/realtime/ws?channels=tickets") as socket:
        assert socket.receive_json()["type"] == "authentication.required"
        socket.send_json({"type": "authenticate", "token": "valid"})
        ready = socket.receive_json()
        assert ready["type"] == "connection.ready"
        assert ready["channels"] == ["tickets"]


def test_chat_channel_requires_and_accepts_authentication(monkeypatch) -> None:
    _accept_test_token(monkeypatch)
    client = TestClient(app)
    with client.websocket_connect("/api/realtime/ws?channels=chat") as socket:
        assert socket.receive_json()["type"] == "authentication.required"
        socket.send_json({"type": "authenticate", "token": "valid"})
        ready = socket.receive_json()
        assert ready["type"] == "connection.ready"
        assert ready["channels"] == ["chat"]


def test_v2_props_connection_gets_current_small_manifest(monkeypatch) -> None:
    _accept_test_token(monkeypatch)
    monkeypatch.setenv("PI_PROP_REVISION_FEED_ENABLED", "true")
    manifest = {
        "contentRevision": "epoch:9",
        "contentDigest": "abc",
        "count": 42,
    }
    monkeypatch.setattr(realtime, "get_json", lambda _key: manifest)
    client = TestClient(app)

    with client.websocket_connect(
        "/api/realtime/ws?channels=props&protocol=2"
    ) as socket:
        assert socket.receive_json()["type"] == "authentication.required"
        socket.send_json({"type": "authenticate", "token": "valid"})
        ready = socket.receive_json()

    assert ready["version"] == 2
    assert ready["manifest"] == manifest


def test_revision_hint_contains_metadata_not_catalog_rows() -> None:
    manifest = {"contentRevision": "epoch:4", "count": 12000}
    event = realtime._revision_event(manifest)

    assert event["type"] == "props.revision"
    assert event["eventId"] == "epoch:4"
    assert event["manifest"] == manifest
    assert "data" not in event


def test_slow_socket_does_not_block_fast_socket(monkeypatch) -> None:
    class _Socket:
        def __init__(self, delay: float) -> None:
            self.delay = delay
            self.messages = []

        async def send_json(self, event) -> None:
            await asyncio.sleep(self.delay)
            self.messages.append(event)

    async def exercise() -> None:
        hub = realtime.LiveHub()
        slow = _Socket(0.05)
        fast = _Socket(0)
        hub.connections = {slow: {"props"}, fast: {"props"}}
        hub.protocols = {slow: 2, fast: 2}
        monkeypatch.setattr(realtime, "_SEND_TIMEOUT_SECONDS", 0.01)

        await hub.broadcast({"type": "props.revision"}, "props")

        assert fast.messages == [{"type": "props.revision"}]
        assert slow not in hub.connections

    asyncio.run(exercise())
