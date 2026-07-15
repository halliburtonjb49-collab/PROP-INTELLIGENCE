import os
from typing import Any

import requests
from dotenv import load_dotenv

load_dotenv()

API_SPORTS_KEY = os.getenv("API_SPORTS_KEY", "").strip()

if not API_SPORTS_KEY:
    raise RuntimeError("API_SPORTS_KEY is missing from .env.")


class ApiSportsProvider:
    def __init__(self, base_url: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.headers = {
            "x-apisports-key": API_SPORTS_KEY,
        }

    def get(
        self,
        endpoint: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        response = requests.get(
            f"{self.base_url}/{endpoint.lstrip('/')}" ,
            headers=self.headers,
            params=params or {},
            timeout=20,
        )
        response.raise_for_status()

        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError("API-Sports returned invalid data.")

        return payload
