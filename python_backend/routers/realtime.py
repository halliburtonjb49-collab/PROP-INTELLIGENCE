"""Shared WebSocket broadcaster for live application state."""

import asyncio
import hashlib
import json
import os
from datetime import datetime, timezone

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services.prop_service import get_props
from services.api_auth_service import resolve_membership
from services.distributed_cache_service import get_json

router = APIRouter(prefix="/api/realtime", tags=["realtime"])
_PROP_MANIFEST_KEY = "props:catalog:manifest:v1"
_SEND_TIMEOUT_SECONDS = 2.0


def _revision_feed_enabled() -> bool:
    return os.getenv("PI_PROP_REVISION_FEED_ENABLED", "false").lower() == "true"


def _revision_event(manifest: dict[str, object]) -> dict[str, object]:
    revision = str(manifest.get("contentRevision") or "")
    return {
        "type": "props.revision",
        "version": 2,
        "eventId": revision,
        "occurredAt": datetime.now(timezone.utc).isoformat(),
        "manifest": manifest,
    }


def _non_soccer_first(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    """Keep realtime updates consistent with the default all-sports HTTP feed."""
    def priority(row: dict[str, object]) -> int:
        sport = str(row.get("sport") or "").strip().upper()
        return 1 if sport == "SOCCER" or sport.startswith("SOCCER_") else 0

    return sorted(rows, key=priority)


class LiveHub:
    def __init__(self) -> None:
        self.connections: dict[WebSocket, set[str]] = {}
        self.user_ids: dict[WebSocket, str] = {}
        self.protocols: dict[WebSocket, int] = {}
        self.publisher: asyncio.Task[None] | None = None
        self.last_digest = ""
        self.last_revision = ""
        self.loop: asyncio.AbstractEventLoop | None = None

    async def connect(self, websocket: WebSocket, channels: set[str], *, user_id: str | None = None,
                      protocol: int = 1,
                      already_accepted: bool = False) -> None:
        if not already_accepted:
            await websocket.accept()
        self.loop = asyncio.get_running_loop()
        self.connections[websocket] = channels
        if user_id is not None:
            self.user_ids[websocket] = user_id
        self.protocols[websocket] = protocol
        ready: dict[str, object] = {
            "type": "connection.ready", "version": protocol,
            "channels": sorted(channels),
            "occurredAt": datetime.now(timezone.utc).isoformat(),
        }
        if protocol >= 2 and "props" in channels and _revision_feed_enabled():
            ready["manifest"] = await asyncio.to_thread(get_json, _PROP_MANIFEST_KEY)
        await websocket.send_json(ready)
        if self.publisher is None or self.publisher.done():
            self.publisher = asyncio.create_task(self.publish_loop())

    def disconnect(self, websocket: WebSocket) -> None:
        self.connections.pop(websocket, None)
        self.user_ids.pop(websocket, None)
        self.protocols.pop(websocket, None)

    async def broadcast(
        self,
        event: dict[str, object],
        channel: str,
        *,
        minimum_protocol: int = 1,
        maximum_protocol: int | None = None,
    ) -> None:
        targets = [
            socket for socket, channels in tuple(self.connections.items())
            if channel in channels
            and self.protocols.get(socket, 1) >= minimum_protocol
            and (
                maximum_protocol is None
                or self.protocols.get(socket, 1) <= maximum_protocol
            )
        ]

        async def send(socket: WebSocket) -> WebSocket | None:
            try:
                await asyncio.wait_for(
                    socket.send_json(event), timeout=_SEND_TIMEOUT_SECONDS
                )
                return None
            except Exception:
                return socket

        stale = await asyncio.gather(*(send(socket) for socket in targets))
        for socket in (value for value in stale if value is not None):
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
                    v2_sockets = [
                        socket for socket, channels in self.connections.items()
                        if "props" in channels and self.protocols.get(socket, 1) >= 2
                    ]
                    if v2_sockets and _revision_feed_enabled():
                        manifest = await asyncio.to_thread(get_json, _PROP_MANIFEST_KEY)
                        revision = str((manifest or {}).get("contentRevision") or "")
                        if revision and revision != self.last_revision:
                            self.last_revision = revision
                            event = _revision_event(manifest)
                            await self.broadcast(event, "props", minimum_protocol=2)
                    legacy = any(
                        "props" in channels and self.protocols.get(socket, 1) < 2
                        for socket, channels in self.connections.items()
                    )
                    if legacy:
                        props = await asyncio.to_thread(get_props)
                        rows = _non_soccer_first(
                            [prop.model_dump(mode="json") for prop in props]
                        )
                        payload = json.dumps(rows, sort_keys=True, default=str)
                        digest = hashlib.sha256(payload.encode()).hexdigest()
                        if digest != self.last_digest:
                            self.last_digest = digest
                            await self.broadcast({"type": "props.updated", "version": 1,
                                                  "eventId": digest[:24],
                                                  "occurredAt": datetime.now(timezone.utc).isoformat(),
                                                  "data": rows}, "props", maximum_protocol=1)
                except Exception:
                    await self.broadcast({"type": "realtime.error", "version": 1,
                                          "occurredAt": datetime.now(timezone.utc).isoformat(),
                                          "message": "Realtime updates are temporarily unavailable"}, "props")
            await asyncio.sleep(2 if _revision_feed_enabled() else 10)
        self.publisher = None


hub = LiveHub()


@router.websocket("/ws")
async def live_updates(websocket: WebSocket, channels: str = "props", protocol: int = 1) -> None:
    requested = {value.strip().lower() for value in channels.split(",") if value.strip()}
    allowed = requested & {"props", "scoreboard", "tickets", "alerts", "sentiment", "chat"}
    user_id = None
    if allowed & {"props", "tickets", "alerts", "chat"}:
        await websocket.accept()
        await websocket.send_json({"type": "authentication.required", "version": 1})
        try:
            auth_message = await asyncio.wait_for(websocket.receive_json(), timeout=10)
            token = str(auth_message.get("token") or "") if isinstance(auth_message, dict) else ""
            membership = await asyncio.to_thread(
                resolve_membership, f"Bearer {token}"
            )
            user_id = membership.user_id if membership.has_core_access else None
        except Exception:
            user_id = None
        if user_id is None:
            await websocket.close(code=4401, reason="Authentication required")
            return
        negotiated = 2 if protocol >= 2 and _revision_feed_enabled() else 1
        await hub.connect(websocket, allowed, user_id=user_id, protocol=negotiated, already_accepted=True)
    else:
        await hub.connect(websocket, allowed)
    try:
        while True:
            message = await websocket.receive_text()
            if message == "ping":
                await websocket.send_json({"type": "pong", "occurredAt": datetime.now(timezone.utc).isoformat()})
    except WebSocketDisconnect:
        hub.disconnect(websocket)
