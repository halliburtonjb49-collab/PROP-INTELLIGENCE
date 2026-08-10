"""Authenticated PROP CHAT to Discord bridge endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from services.api_auth_service import require_user_id
from services.discord_bridge_service import discord_bridge, trusted_chat_username

router = APIRouter(prefix="/api/realtime/discord", tags=["realtime"])


class DiscordChatMessage(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    room_id: str = Field(default="general", alias="roomId", max_length=64)


@router.post("/messages")
async def mirror_message(
    payload: DiscordChatMessage,
    user_id: str = Depends(require_user_id),
) -> dict[str, object]:
    if payload.room_id != "general":
        raise HTTPException(status_code=400, detail="Only General chat mirrors to Discord")
    try:
        message_id = await discord_bridge.send(
            username=trusted_chat_username(user_id),
            text=payload.text,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {"status": "sent", "messageId": message_id}


@router.get("/health")
def discord_bridge_health(_user_id: str = Depends(require_user_id)) -> dict[str, object]:
    return discord_bridge.health()