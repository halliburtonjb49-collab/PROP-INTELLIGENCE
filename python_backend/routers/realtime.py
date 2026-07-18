"""Shared WebSocket broadcaster for live application state."""

import asyncio
import hashlib
import json
from datetime import datetime, timezone

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services.prop_service import get_props
from services.api_auth_service import verify_supabase_token

router = APIRouter(prefix="/api/realtime", tags=["realtime"])


class LiveHub:
    def __init__(self) -> None:
        self.connections: dict[WebSocket, set[str]] = {}
        self.user_ids: dict[WebSocket, str] = {}
        self.publisher: asyncio.Task[None] | None = None
        self.last_digest = ""
        self.loop: asyncio.AbstractEventLoop | None = None

    async def connect(self, websocket: WebSocket, channels: set[str], *, user_id: str | None = None,
                      already_accepted: bool = False) -> None:
        if not already_accepted:
            await websocket.accept()
        self.loop = asyncio.get_running_loop()
        self.connections[websocket] = channels
        if user_id is not None:
            self.user_ids[websocket] = user_id
        await websocket.send_json({"type": "connection.ready", "version": 1,
                                   "channels": sorted(channels),
                                   "occurredAt": datetime.now(timezone.utc).isoformat()})
        if self.publisher is None or self.publisher.done():
            self.publisher = asyncio.create_task(self.publish_loop())

    def disconnect(self, websocket: WebSocket) -> None:
        self.connections.pop(websocket, None)
        self.user_ids.pop(websocket, None)

    async def broadcast(self, event: dict[str, object], channel: str) -> None:
        stale = []
        for socket, channels in tuple(self.connections.items()):
            if channel not in channels:
                continue
            try:
                await socket.send_json(event)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect(socket)

    def broadcast_from_thread(self, event: dict[str, object], channel: str) -> None:
        if self.loop is not None and self.loop.is_running() and self.connections:
            asyncio.run_coroutine_threadsafe(self.broadcast(event, channel), self.loop)

    async def broadcast_user(self, event: dict[str, object], channel: str, user_id: str) -> None:
        stale = []
        for socket, channels in tuple(self.connections.items()):
            if channel not in channels or self.user_ids.get(socket) != user_id:
                continue
            try:
                await socket.send_json(event)
            except Exception:
                stale.append(socket)
        for socket in stale:
            self.disconnect(socket)

    def broadcast_user_from_thread(self, event: dict[str, object], channel: str, user_id: str) -> None:
        if self.loop is not None and self.loop.is_running() and self.connections:
            asyncio.run_coroutine_threadsafe(self.broadcast_user(event, channel, user_id), self.loop)

    async def publish_loop(self) -> None:
        while self.connections:
            prop_subscribers = any("props" in channels for channels in self.connections.values())
            if prop_subscribers:
                try:
                    props = await asyncio.to_thread(get_props)
                    rows = [prop.model_dump(mode="json") for prop in props]
                    payload = json.dumps(rows, sort_keys=True, default=str)
                    digest = hashlib.sha256(payload.encode()).hexdigest()
                    if digest != self.last_digest:
                        self.last_digest = digest
                        await self.broadcast({"type": "props.updated", "version": 1,
                                              "eventId": digest[:24],
                                              "occurredAt": datetime.now(timezone.utc).isoformat(),
                                              "data": rows}, "props")
                except Exception as exc:
                    await self.broadcast({"type": "realtime.error", "version": 1,
                                          "occurredAt": datetime.now(timezone.utc).isoformat(),
                                          "message": str(exc)}, "props")
            await asyncio.sleep(10)
        self.publisher = None


hub = LiveHub()


@router.websocket("/ws")
async def live_updates(websocket: WebSocket, channels: str = "props") -> None:
    requested = {value.strip().lower() for value in channels.split(",") if value.strip()}
    allowed = requested & {"props", "scoreboard", "tickets", "alerts", "sentiment"}
    user_id = None
    if allowed & {"tickets", "alerts"}:
        await websocket.accept()
        await websocket.send_json({"type": "authentication.required", "version": 1})
        try:
            auth_message = await asyncio.wait_for(websocket.receive_json(), timeout=10)
            token = str(auth_message.get("token") or "") if isinstance(auth_message, dict) else ""
            user_id = await asyncio.to_thread(verify_supabase_token, token)
        except Exception:
            user_id = None
        if user_id is None:
            await websocket.close(code=4401, reason="Authentication required")
            return
        await hub.connect(websocket, allowed, user_id=user_id, already_accepted=True)
    else:
        await hub.connect(websocket, allowed or {"props"})
    try:
        while True:
            message = await websocket.receive_text()
            if message == "ping":
                await websocket.send_json({"type": "pong", "occurredAt": datetime.now(timezone.utc).isoformat()})
    except WebSocketDisconnect:
        hub.disconnect(websocket)
