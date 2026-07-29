"""Send a secret-safe deployment or health alert to the operator webhook."""
import json
import os
import sys
import urllib.request


def main() -> int:
    webhook = os.getenv("OPERATIONS_ALERT_WEBHOOK_URL", "").strip()
    if not webhook:
        print("OPERATIONS_ALERT_WEBHOOK_URL is not configured; alert skipped.")
        return 0
    event = os.getenv("OPERATIONS_ALERT_EVENT", "production-check-failed")
    details = os.getenv("OPERATIONS_ALERT_DETAILS", "")[:1000]
    payload = json.dumps(
        {
            "text": f"PROP INTELLIGENCE ALERT: {event}",
            "event": event,
            "details": details,
            "repository": os.getenv("GITHUB_REPOSITORY", ""),
            "runUrl": (
                f"{os.getenv('GITHUB_SERVER_URL', '')}/"
                f"{os.getenv('GITHUB_REPOSITORY', '')}/actions/runs/"
                f"{os.getenv('GITHUB_RUN_ID', '')}"
            ),
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        webhook,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        if not 200 <= response.status < 300:
            raise RuntimeError(f"Alert webhook returned HTTP {response.status}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Operations alert failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
