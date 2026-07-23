"""Trigger the web service to refresh its PGA player roster cache.

Same reasoning as the other sync scripts: this cron job and the API are
separate Render deployments with no shared filesystem, so the refresh has
to happen inside the API process via an authenticated HTTP call - see
main.py's /api/admin/refresh-golf-roster and
services/sportsdataio_golf_service.py.
"""

import logging

from _admin_refresh_utils import trigger_and_await_refresh


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    try:
        payload = trigger_and_await_refresh("/api/admin/refresh-golf-roster")
    except Exception:
        logging.exception("PGA roster sync failed")
        return 1

    logging.info("Cached PGA roster for %s players", payload.get("result"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
