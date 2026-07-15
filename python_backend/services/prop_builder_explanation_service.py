import json
from collections import defaultdict
from typing import Any

from services.market_normalizer import (
    normalize_market,
)
from services.prop_builder_history_service import (
    _connect,
    initialize_prop_builder_history,
)


def get_market_performance_lookup() -> dict[str, dict[str, float | int]]:
    initialize_prop_builder_history()
    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT legs_json
            FROM prop_builder_history
            """
        ).fetchall()

    totals: dict[
        str,
        dict[str, int],
    ] = defaultdict(
        lambda: {
            "won": 0,
            "lost": 0,
            "push": 0,
        }
    )

    for row in rows:
        legs = json.loads(
            row["legs_json"]
        )
        for leg in legs:
            if not isinstance(leg, dict):
                continue

            status = str(
                leg.get(
                    "result_status",
                    "pending",
                )
            ).lower()
            if status not in {
                "won",
                "lost",
                "push",
            }:
                continue

            market = normalize_market(
                str(
                    leg.get(
                        "market",
                        "",
                    )
                )
            )
            if not market:
                continue

            totals[market][status] += 1

    lookup: dict[
        str,
        dict[str, float | int],
    ] = {}
    for market, values in totals.items():
        resolved = (
            values["won"]
            + values["lost"]
            + values["push"]
        )
        hit_rate = (
            round(
                values["won"]
                / resolved
                * 100,
                1,
            )
            if resolved
            else 0
        )
        lookup[market] = {
            "hit_rate": hit_rate,
            "sample_size": resolved,
        }

    return lookup
