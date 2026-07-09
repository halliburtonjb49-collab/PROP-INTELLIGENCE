from __future__ import annotations

from typing import Any

import httpx

from app.config import settings


class SportsDataIOService:
    def __init__(self) -> None:
        self.api_key = settings.sportsdataio_api_key
        print("SportsDataIO key loaded:", bool(settings.sportsdataio_api_key))

    async def get_json(self, url: str) -> Any:
        if not self.api_key:
            raise RuntimeError("SPORTSDATAIO_API_KEY is missing.")

        headers = {
            "Ocp-Apim-Subscription-Key": self.api_key,
        }
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(url, headers=headers)
            response.raise_for_status()
            return response.json()


sportsdataio_service = SportsDataIOService()
