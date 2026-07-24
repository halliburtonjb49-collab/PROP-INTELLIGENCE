"""Refresh the ESPN headshot cache (NBA/WNBA/NHL/PGA/UFC).

This cron job and the API service are separate Render deployments with no
shared filesystem, so the refresh has to happen inside the API process via
an authenticated HTTP call - see main.py's /api/admin/refresh-espn-headshots
and services/espn_headshot_service.py. Roster changes are infrequent
(trades, call-ups), so this only needs to run on a daily-ish schedule.
"""

import logging

from _admin_refresh_utils import trigger_and_await_refresh


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    try:
        payload = trigger_and_await_refresh("/api/admin/refresh-espn-headshots")
    except Exception:
        logging.exception("ESPN headshot roster sync failed")
        return 1

    logging.info("Cached ESPN headshot ids: %s", payload.get("result"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
