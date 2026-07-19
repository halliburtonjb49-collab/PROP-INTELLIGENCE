"""Run non-destructive production checks after a release."""

from __future__ import annotations

import json
import os
from urllib.request import Request, urlopen


def fetch(url: str, *, admin_key: str = "") -> tuple[int, object]:
    headers = {"X-Admin-Key": admin_key} if admin_key else {}
    with urlopen(Request(url, headers=headers), timeout=30) as response:  # noqa: S310
        body = response.read().decode("utf-8")
        try:
            return response.status, json.loads(body)
        except json.JSONDecodeError:
            return response.status, body[:200]


def main() -> int:
    api = os.getenv("API_BASE_URL", "https://api.propsintell.com").rstrip("/")
    app = os.getenv("APP_BASE_URL", "https://app.propsintell.com").rstrip("/")
    admin_key = os.getenv("ADMIN_API_KEY", "").strip()
    checks = {
        "apiHealth": fetch(f"{api}/health"),
        "props": fetch(f"{api}/api/props"),
        "gameMarkets": fetch(f"{api}/api/game-markets?sport=MLB"),
        "propFeedHealth": fetch(f"{api}/api/operations/prop-feed-health"),
        "gameMarketHealth": fetch(f"{api}/api/operations/game-market-health"),
        "accuracyAudit": fetch(f"{api}/api/accuracy/audit"),
        "calibration": fetch(f"{api}/api/intelligence/calibration"),
        "webApp": fetch(app),
    }
    if admin_key:
        checks["readiness"] = fetch(f"{api}/api/operations/readiness", admin_key=admin_key)
        checks["pipelines"] = fetch(f"{api}/api/operations/pipelines", admin_key=admin_key)
    print(json.dumps(checks, indent=2, default=str))
    failed = [name for name, (status, _) in checks.items() if status < 200 or status >= 400]
    props_payload = checks["props"][1]
    if not isinstance(props_payload, dict) or int(props_payload.get("count", 0)) <= 0:
        failed.append("props-empty")
    prop_health = checks["propFeedHealth"][1]
    if not isinstance(prop_health, dict) or prop_health.get("status") != "ok":
        failed.append("prop-feed-unhealthy")
    game_health = checks["gameMarketHealth"][1]
    if not isinstance(game_health, dict) or game_health.get("status") not in {"ok", "degraded"}:
        failed.append("game-market-monitor-unavailable")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
