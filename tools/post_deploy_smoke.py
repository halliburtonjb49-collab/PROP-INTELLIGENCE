import json
import sys
import time
import urllib.request
from datetime import datetime, timezone


APP_URL = "https://app.propsintell.com"
API_URL = "https://api.propsintell.com"
MAX_PROP_FEED_AGE_MINUTES = 45


def request(url: str, *, method: str = "GET", headers: dict[str, str] | None = None):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    started = time.perf_counter()
    response = urllib.request.urlopen(req, timeout=20)
    body = response.read()
    return response, body, (time.perf_counter() - started) * 1000


def main() -> int:
    health, health_body, health_ms = request(f"{API_URL}/health")
    health_payload = json.loads(health_body)
    if health.status != 200 or health_payload.get("status") != "ok":
        raise RuntimeError("API health check is unavailable")
    if health_payload.get("ticket_storage_mode") != "persistent-disk":
        raise RuntimeError(
            "Production ticket storage is not using the persistent disk"
        )
    app, html, app_ms = request(APP_URL)
    if app.status != 200 or b"flutter_bootstrap.js" not in html:
        raise RuntimeError("Web application shell is unavailable")

    cors, _, _ = request(
        f"{API_URL}/api/props?limit=1",
        method="OPTIONS",
        headers={
            "Origin": APP_URL,
            "Access-Control-Request-Method": "GET",
        },
    )
    if cors.headers.get("Access-Control-Allow-Origin") != APP_URL:
        raise RuntimeError("Production CORS origin is not allowed")

    props, body, props_ms = request(
        f"{API_URL}/api/props?sportsbook=PRIZEPICKS&limit=75&offset=0"
    )
    payload = json.loads(body)
    if props.status != 200 or not payload.get("props"):
        raise RuntimeError("PrizePicks initial prop page is empty or unavailable")
    if len(body) > 300_000:
        raise RuntimeError(f"Initial prop payload exceeds 300 KB: {len(body)} bytes")
    if props_ms > 5_000:
        raise RuntimeError(f"Initial prop request exceeds 5 seconds: {props_ms:.0f} ms")

    # A freshly deployed API instance starts with empty in-memory feed metrics.
    # Read health again after the real prop request so the freshness assertion
    # measures the live request instead of treating a cold start as a failure.
    feed_health, feed_health_body, _ = request(f"{API_URL}/health")
    feed_health_payload = json.loads(feed_health_body)
    if feed_health.status != 200:
        raise RuntimeError("API health check failed after loading props")
    prop_feed = feed_health_payload.get("propFeed") or {}
    if prop_feed.get("lastRequestSucceeded") is not True:
        raise RuntimeError("The most recent production prop-feed request failed")
    last_data_updated = prop_feed.get("lastDataUpdatedAt")
    if not last_data_updated:
        raise RuntimeError("Production prop-feed freshness is unavailable")
    last_data_at = datetime.fromisoformat(
        str(last_data_updated).replace("Z", "+00:00")
    )
    if last_data_at.tzinfo is None:
        last_data_at = last_data_at.replace(tzinfo=timezone.utc)
    feed_age_minutes = (
        datetime.now(timezone.utc) - last_data_at
    ).total_seconds() / 60
    if feed_age_minutes > MAX_PROP_FEED_AGE_MINUTES:
        raise RuntimeError(
            "Production prop feed is stale: "
            f"{feed_age_minutes:.0f} minutes old"
        )

    bundle, javascript, _ = request(f"{APP_URL}/main.dart.js")
    lowered = javascript.lower()
    if bundle.status != 200 or b"localhost" in lowered or b"127.0.0.1" in lowered:
        raise RuntimeError("Production JavaScript contains a local backend address")
    if b"api.propsintell.com" not in lowered:
        raise RuntimeError("Production API domain is missing from the web bundle")

    print(
        json.dumps(
            {
                "status": "ok",
                "healthMs": round(health_ms),
                "appMs": round(app_ms),
                "propsMs": round(props_ms),
                "payloadBytes": len(body),
                "props": len(payload["props"]),
                "feedAgeMinutes": round(feed_age_minutes),
                "version": props.headers.get("X-App-Version", "unknown"),
            }
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"production smoke failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
