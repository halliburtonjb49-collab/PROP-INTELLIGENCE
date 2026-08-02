from typing import Literal

from pydantic import BaseModel, Field


class TicketSyncDiagnostic(BaseModel):
    phase: Literal["localDraft", "syncing", "synced", "error"]
    error_category: Literal[
        "network", "timeout", "authentication", "conflict", "server", "unknown"
    ] = "unknown"
    attempts: int = Field(default=0, ge=0, le=50)
    client_request_id: str = Field(default="", max_length=128)
    platform: str = Field(default="unknown", max_length=40)
