"""Shared helper for admin-triggered background refresh jobs.

The refresh endpoints in main.py (see _BackgroundJob) start their work via
BackgroundTasks and return immediately rather than blocking the request -
some of these roster walks (Sportmonks: 6 leagues x ~20 teams each) take
long enough that running them inline would risk Render's proxy timing out
the connection and returning a 502 before the work even finishes. This
mirrors the existing /api/sync + /api/sync/status polling pattern already
used by sync_pregame.py.
"""

import os
import time

import requests


def resolve_api_base_url() -> str:
    api_base_url = os.getenv("API_BASE_URL", "").strip().rstrip("/")
    if not api_base_url and os.getenv("RENDER", "").lower() == "true":
        api_base_url = "https://api.propsintell.com"
    return api_base_url


def trigger_and_await_refresh(
    endpoint_path: str,
    *,
    timeout_seconds: int = 600,
    poll_interval_seconds: int = 5,
) -> dict[str, object]:
    """POSTs to start a background refresh, then polls its /status endpoint
    until the job reports complete or failed. Raises on any failure.
    """
    api_base_url = resolve_api_base_url()
    admin_key = os.getenv("ADMIN_API_KEY", "").strip()
    if not api_base_url or not admin_key:
        raise RuntimeError("API_BASE_URL and ADMIN_API_KEY are required")

    headers = {"X-Admin-Key": admin_key}
    status_url = f"{api_base_url}{endpoint_path}/status"

    start_response = requests.post(f"{api_base_url}{endpoint_path}", headers=headers, timeout=30)
    start_response.raise_for_status()
    payload = start_response.json()
    status = str(payload.get("status", "")).lower()
    if status == "complete":
        return payload
    if status == "failed":
        raise RuntimeError(str(payload.get("error") or "Refresh failed to start"))

    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        time.sleep(poll_interval_seconds)
        status_response = requests.get(status_url, headers=headers, timeout=30)
        status_response.raise_for_status()
        payload = status_response.json()
        status = str(payload.get("status", "")).lower()
        if status == "complete":
            return payload
        if status == "failed":
            raise RuntimeError(str(payload.get("error") or "Refresh failed"))

    raise TimeoutError(f"Refresh at {endpoint_path} did not finish within {timeout_seconds}s")
