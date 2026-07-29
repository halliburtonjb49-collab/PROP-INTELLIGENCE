import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone


APP_URL = "https://app.propsintell.com"
API_URL = "https://api.propsintell.com"
MAX_PROP_FEED_AGE_MINUTES = 45
DEFAULT_TRANSIENT_ATTEMPTS = 6
MAX_RETRY_DELAY_SECONDS = 10
TRANSIENT_HTTP_STATUSES = {502, 503, 504}


def _retry_delay(attempt: int) -> int:
    return min(2 ** (attempt + 1), MAX_RETRY_DELAY_SECONDS)


def request(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    transient_attempts: int = DEFAULT_TRANSIENT_ATTEMPTS,
):
    for attempt in range(transient_attempts):
        req = urllib.request.Request(url, method=method, headers=headers or {})
        started = time.perf_counter()
        try:
            response = urllib.request.urlopen(req, timeout=20)
            body = response.read()
            return response, body, (time.perf_counter() - started) * 1000
        except urllib.error.HTTPError as exc:
            if (
                exc.code not in TRANSIENT_HTTP_STATUSES
                or attempt + 1 >= transient_attempts
            ):
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt + 1 >= transient_attempts:
                raise
        delay = _retry_delay(attempt)
        print(
            f"temporary production response; retrying {url} in {delay}s "
            f"({attempt + 2}/{transient_attempts})",
            file=sys.stderr,
        )
        time.sleep(delay)
    raise RuntimeError("Production request exhausted transient retries")


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

    readiness, body, props_ms = request(
        f"{API_URL}/api/props/readiness"
    )
    payload = json.loads(body)
    if (
        readiness.status != 200
        or payload.get("status") != "ok"
        or int(payload.get("count") or 0) < 1
    ):
        raise RuntimeError("Protected production prop feed is empty or unavailable")
    if payload.get("dataProtected") is not True:
        raise RuntimeError("Production readiness endpoint does not confirm data protection")
    if len(body) > 20_000:
        raise RuntimeError(f"Readiness payload exceeds 20 KB: {len(body)} bytes")
    server_ms = float(payload.get("responseMs") or 0)
    if server_ms > 5_000:
        raise RuntimeError(
            f"Prop readiness processing exceeds 5 seconds: {server_ms:.0f} ms"
        )
    if props_ms > 10_000:
        raise RuntimeError(
            f"Prop readiness round trip exceeds 10 seconds: {props_ms:.0f} ms"
        )

    # The proprietary feed must remain unavailable without a real user session.
    try:
        request(f"{API_URL}/api/props?limit=1")
    except urllib.error.HTTPError as exc:
        if exc.code != 401:
            raise RuntimeError(
                f"Protected prop feed returned unexpected HTTP {exc.code}"
            ) from exc
    else:
        raise RuntimeError("Production prop feed is anonymously accessible")

    last_data_updated = payload.get("lastDataUpdatedAt")
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
                "propsServerMs": round(server_ms),
                "payloadBytes": len(body),
                "props": int(payload["count"]),
                "feedAgeMinutes": round(feed_age_minutes),
                "version": payload.get("version", "unknown"),
                "dataProtected": True,
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
