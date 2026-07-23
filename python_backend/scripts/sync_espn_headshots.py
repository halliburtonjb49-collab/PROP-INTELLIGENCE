"""Trigger the web service to refresh its ESPN headshot cache (NBA/WNBA/NHL).

Same reasoning as sync_mlb_headshots.py: this cron job and the API are
separate Render deployments with no shared filesystem, so the refresh has
to happen inside the API process via an authenticated HTTP call - see
main.py's /api/admin/refresh-espn-headshots and
services/espn_headshot_service.py.
"""

import logging
import os

import requests


def main() -> int:
    logging.basicConfig(level=logging.INFO)

    api_base_url = os.getenv("API_BASE_URL", "").strip().rstrip("/")
    if not api_base_url and os.getenv("RENDER", "").lower() == "true":
        api_base_url = "https://api.propsintell.com"
    admin_key = os.getenv("ADMIN_API_KEY", "").strip()
    if not api_base_url or not admin_key:
        logging.error("API_BASE_URL and ADMIN_API_KEY are required")
        return 1

    try:
        response = requests.post(
            f"{api_base_url}/api/admin/refresh-espn-headshots",
            headers={"X-Admin-Key": admin_key},
            timeout=180,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception:
        logging.exception("ESPN headshot roster sync failed")
        return 1

    logging.info("Cached ESPN headshot ids: %s", payload.get("playerCounts"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
