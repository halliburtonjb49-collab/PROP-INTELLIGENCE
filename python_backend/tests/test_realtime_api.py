from fastapi.testclient import TestClient

from main import app


def test_websocket_protocol_connects_and_pongs() -> None:
    client = TestClient(app)
    with client.websocket_connect("/api/realtime/ws?channels=props,unknown") as socket:
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


def test_ticket_channel_requires_and_accepts_authentication(monkeypatch) -> None:
    monkeypatch.setattr("routers.realtime.verify_supabase_token", lambda token: "user-1" if token == "valid" else None)
    client = TestClient(app)
    with client.websocket_connect("/api/realtime/ws?channels=tickets") as socket:
        assert socket.receive_json()["type"] == "authentication.required"
        socket.send_json({"type": "authenticate", "token": "valid"})
        ready = socket.receive_json()
        assert ready["type"] == "connection.ready"
        assert ready["channels"] == ["tickets"]
