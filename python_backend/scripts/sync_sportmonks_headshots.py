"""Trigger the web service to refresh its Sportmonks soccer headshot cache.

Same reasoning as the other headshot sync scripts: this cron job and the
API are separate Render deployments with no shared filesystem, so the
refresh has to happen inside the API process via an authenticated HTTP
call - see main.py's /api/admin/refresh-sportmonks-headshots and
services/sportmonks_headshot_service.py.
"""

import logging

from _admin_refresh_utils import trigger_and_await_refresh


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    try:
        payload = trigger_and_await_refresh(
            "/api/admin/refresh-sportmonks-headshots",
            timeout_seconds=900,
        )
    except Exception:
        logging.exception("Sportmonks headshot roster sync failed")
        return 1

    logging.info("Cached Sportmonks headshot counts by league: %s", payload.get("result"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
