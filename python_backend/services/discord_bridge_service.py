"""Optional, authenticated bridge between PROP CHAT and Discord."""

from __future__ import annotations

import asyncio
import logging
import os
import re
from collections.abc import Awaitable, Callable
from datetime import timezone

import discord

from database.postgres import database_is_configured, get_database_pool

LOGGER = logging.getLogger(__name__)
DiscordMessageHandler = Callable[[dict[str, object]], Awaitable[None]]


def _clean_username(value: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9_]+", "_", value.strip()).strip("_").lower()
    return (cleaned or "member")[:24]


def trusted_chat_username(user_id: str) -> str:
    """Resolve a public username from server-owned profile data."""
    fallback = f"member_{user_id.replace('-', '')[:8]}"
    if not database_is_configured():
        return fallback
    try:
        with get_database_pool().connection(timeout=10) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """select coalesce(nullif(trim(username), ''),
                                              nullif(trim(display_name), ''))
                       from public.user_profiles where id=%s limit 1""",
                    (user_id,),
                )
                row = cursor.fetchone()
        return _clean_username(str(row[0])) if row and row[0] else fallback
    except Exception as exc:
        LOGGER.warning("Discord bridge username lookup failed error=%s", type(exc).__name__)
        return fallback


class DiscordBridge:
    def __init__(self) -> None:
        self._client: discord.Client | None = None
        self._task: asyncio.Task[None] | None = None
        self._handler: DiscordMessageHandler | None = None

    @property
    def token(self) -> str:
        return os.getenv("DISCORD_BOT_TOKEN", "").strip()

    @property
    def channel_id(self) -> int | None:
        raw = os.getenv("DISCORD_CHANNEL_ID", "").strip()
        try:
            value = int(raw)
        except ValueError:
            return None
        return value if value > 0 else None

    @property
    def configured(self) -> bool:
        return bool(self.token and self.channel_id)

    @property
    def connected(self) -> bool:
        return bool(self._client and self._client.is_ready())

    def set_message_handler(self, handler: DiscordMessageHandler) -> None:
        self._handler = handler

    async def start(self) -> None:
        if not self.configured:
            LOGGER.info("Discord bridge disabled; token or numeric channel ID is not configured")
            return
        if self._task and not self._task.done():
            return
        intents = discord.Intents.default()
        intents.message_content = True
        client = discord.Client(intents=intents)
        self._client = client

        @client.event
        async def on_ready() -> None:
            LOGGER.info("Discord bridge connected bot_user_id=%s", getattr(client.user, "id", None))

        @client.event
        async def on_message(message: discord.Message) -> None:
            if message.author.bot:
                return
            if message.channel.id != self.channel_id or not message.content.strip():
                return
            if self._handler is None:
                return
            await self._handler({
                "type": "chat.discord.message",
                "version": 1,
                "eventId": str(message.id),
                "occurredAt": message.created_at.astimezone(timezone.utc).isoformat(),
                "data": {
                    "id": str(message.id),
                    "userId": f"discord:{message.author.id}",
                    "username": _clean_username(message.author.display_name),
                    "body": message.content.strip()[:500],
                    "roomId": "general",
                    "source": "discord",
                },
            })

        async def run_client() -> None:
            try:
                await client.start(self.token)
            except asyncio.CancelledError:
                raise
            except Exception:
                LOGGER.exception("Discord bridge stopped unexpectedly")

        self._task = asyncio.create_task(run_client(), name="discord-bridge")

    async def stop(self) -> None:
        client, task = self._client, self._task
        self._client = None
        self._task = None
        if client is not None and not client.is_closed():
            await client.close()
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

    async def send(self, *, username: str, text: str) -> str:
        if not self.configured:
            raise RuntimeError("Discord bridge is not configured")
        client = self._client
        if client is None:
            raise RuntimeError("Discord bridge is not running")
        try:
            await asyncio.wait_for(client.wait_until_ready(), timeout=10)
        except TimeoutError as exc:
            raise RuntimeError("Discord bridge is not connected") from exc
        channel = client.get_channel(self.channel_id or 0)
        if channel is None:
            channel = await client.fetch_channel(self.channel_id or 0)
        if not isinstance(channel, discord.abc.Messageable):
            raise RuntimeError("Configured Discord channel cannot receive messages")
        safe_name = discord.utils.escape_markdown(_clean_username(username))
        safe_text = discord.utils.escape_mentions(text.strip()[:500])
        message = await channel.send(
            f"**[{safe_name} via PROP INTELLIGENCE]:** {safe_text}",
            allowed_mentions=discord.AllowedMentions.none(),
        )
        return str(message.id)

    def health(self) -> dict[str, object]:
        return {
            "configured": self.configured,
            "connected": self.connected,
            "channelConfigured": self.channel_id is not None,
        }


discord_bridge = DiscordBridge()