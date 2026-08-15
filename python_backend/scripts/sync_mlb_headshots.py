"""Refresh MLB headshots in this isolated cron process and publish to Redis.

No provider requests execute in the web service.
"""

import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.mlb_headshot_service import refresh_mlb_headshot_map


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    try:
        players = refresh_mlb_headshot_map()
    except Exception:
        logging.exception("MLB headshot roster sync failed")
        return 1

    logging.info("Cached headshot ids for %s MLB players", players)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
