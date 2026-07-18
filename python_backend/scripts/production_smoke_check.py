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
        "calibration": fetch(f"{api}/api/intelligence/calibration"),
        "webApp": fetch(app),
    }
    if admin_key:
        checks["readiness"] = fetch(f"{api}/api/operations/readiness", admin_key=admin_key)
        checks["pipelines"] = fetch(f"{api}/api/operations/pipelines", admin_key=admin_key)
    print(json.dumps(checks, indent=2, default=str))
    failed = [name for name, (status, _) in checks.items() if status < 200 or status >= 400]
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
