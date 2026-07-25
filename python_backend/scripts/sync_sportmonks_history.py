"""Trigger the full-season soccer-history backfill on the API service."""

import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts._admin_refresh_utils import trigger_and_await_refresh


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    try:
        payload = trigger_and_await_refresh(
            "/api/admin/refresh-sportmonks-history",
            timeout_seconds=900,
        )
        logging.info("Soccer history refresh completed: %s", payload)
        return 0
    except Exception:
        logging.exception("Soccer history refresh failed")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
