"""Refresh ESPN headshots in this isolated cron process and publish to Redis.

No provider requests execute in the web service.
"""

import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.espn_headshot_service import refresh_espn_headshot_map


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    try:
        leagues = refresh_espn_headshot_map()
    except Exception:
        logging.exception("ESPN headshot roster sync failed")
        return 1

    logging.info("Cached ESPN headshot ids: %s", leagues)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
