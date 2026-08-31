import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone


APP_URL = "https://pipropsintell.com/workspace"
SITE_URL = "https://pipropsintell.com"
API_URL = "https://api.propsintell.com"

# This gate must be reachable by the refresh policy that feeds it, or deploys
# fail on a bound the system cannot hold. The worst case age is the watchdog's
# refresh threshold, plus the 15-minute window it deduplicates jobs into, plus
# the time a sync takes to run. A gate tighter than that sum rejects healthy
# deployments; this was set to 45 while the refresh threshold was 180.
PROP_FEED_REFRESH_AFTER_MINUTES = int(
    os.getenv("PROP_FEED_REFRESH_AFTER_MINUTES", "30")
)
PROP_FEED_REFRESH_DEDUPE_MINUTES = 15
PROP_FEED_SYNC_ALLOWANCE_MINUTES = 10
MAX_PROP_FEED_AGE_MINUTES = (
    PROP_FEED_REFRESH_AFTER_MINUTES
    + PROP_FEED_REFRESH_DEDUPE_MINUTES
    + PROP_FEED_SYNC_ALLOWANCE_MINUTES
)
DEFAULT_TRANSIENT_ATTEMPTS = 12
MAX_RETRY_DELAY_SECONDS = 10
TRANSIENT_HTTP_STATUSES = {502, 503, 504}
DEPLOYMENT_POLL_SECONDS = 10


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


def wait_for_expected_version() -> None:
    expected_version = os.getenv("EXPECTED_PRODUCTION_VERSION", "").strip()
    if not expected_version:
        return
    wait_seconds = int(os.getenv("PRODUCTION_DEPLOY_WAIT_SECONDS", "600"))
    deadline = time.monotonic() + wait_seconds
    last_observation = "production API did not respond"
    while time.monotonic() < deadline:
        try:
            response, body, _ = request(
                f"{API_URL}/health",
                transient_attempts=1,
            )
            payload = json.loads(body)
            actual_version = str(payload.get("version") or "")
            if (
                response.status == 200
                and payload.get("status") == "ok"
                and actual_version == expected_version
            ):
                return
            last_observation = (
                f"expected version {expected_version}, received "
                f"{actual_version or 'unknown'}"
            )
        except (
            json.JSONDecodeError,
            urllib.error.HTTPError,
            urllib.error.URLError,
            TimeoutError,
        ) as exc:
            last_observation = str(exc)
        time.sleep(DEPLOYMENT_POLL_SECONDS)
    raise RuntimeError(
        "Production deployment did not become active within "
        f"{wait_seconds} seconds: {last_observation}"
    )


def _feed_age_minutes(payload: dict) -> float:
    # A provider can legitimately return the same line across consecutive
    # successful syncs. In that case lastDataUpdatedAt does not move even
    # though a fresh protected catalog was generated and published. Certify
    # the publication timestamp when available while retaining the provider
    # timestamp in readiness for data-quality monitoring.
    last_data_updated = (
        payload.get("catalogPublishedAt")
        or payload.get("lastDataUpdatedAt")
    )
    if not last_data_updated:
        raise RuntimeError("Production prop-feed freshness is unavailable")
    last_data_at = datetime.fromisoformat(
        str(last_data_updated).replace("Z", "+00:00")
    )
    if last_data_at.tzinfo is None:
        last_data_at = last_data_at.replace(tzinfo=timezone.utc)
    return (
        datetime.now(timezone.utc) - last_data_at
    ).total_seconds() / 60


def read_fresh_prop_readiness() -> tuple[object, bytes, float, dict, float]:
    warmup_seconds = int(os.getenv("PRODUCTION_FEED_WARMUP_SECONDS", "0"))
    deadline = time.monotonic() + warmup_seconds
    while True:
        readiness, body, props_ms = request(
            f"{API_URL}/api/props/readiness"
        )
        payload = json.loads(body)
        feed_age_minutes = _feed_age_minutes(payload)
        server_ms = float(payload.get("responseMs") or 0)
        feed_is_ready = feed_age_minutes <= MAX_PROP_FEED_AGE_MINUTES
        performance_is_ready = server_ms <= 5_000 and props_ms <= 10_000
        if feed_is_ready and performance_is_ready:
            return readiness, body, props_ms, payload, feed_age_minutes
        if time.monotonic() >= deadline:
            if not feed_is_ready:
                # Name the serving layer. A stale feed served from the
                # durable snapshot means the shared catalog could not be
                # reached at all, which is a different failure from a sync
                # that simply has not run -- and today that distinction cost
                # an hour of looking in the wrong place.
                source = str(payload.get("source") or "unreported")
                raise RuntimeError(
                    "Production prop feed is stale: "
                    f"{feed_age_minutes:.0f} minutes old "
                    f"(serving layer: {source})"
                )
            if server_ms > 5_000:
                raise RuntimeError(
                    "Prop readiness processing exceeds 5 seconds: "
                    f"{server_ms:.0f} ms"
                )
            raise RuntimeError(
                "Prop readiness round trip exceeds 10 seconds: "
                f"{props_ms:.0f} ms"
            )
        reason = (
            "feed freshness"
            if not feed_is_ready
            else "cold-cache performance"
        )
        print(
            f"production {reason} is warming; retrying readiness check in "
            f"{DEPLOYMENT_POLL_SECONDS}s",
            file=sys.stderr,
        )
        time.sleep(DEPLOYMENT_POLL_SECONDS)


def main() -> int:
    wait_for_expected_version()
    health, health_body, health_ms = request(f"{API_URL}/health")
    health_payload = json.loads(health_body)
    if health.status != 200 or health_payload.get("status") != "ok":
        raise RuntimeError("API health check is unavailable")
    readiness, readiness_body, _ = request(f"{API_URL}/ready")
    readiness_payload = json.loads(readiness_body)
    if readiness.status != 200 or readiness_payload.get("ready") is not True:
        raise RuntimeError("API dependencies are not ready")
    ticket_storage = (
        readiness_payload.get("checks", {}).get("ticketStorage", {})
    )
    if ticket_storage.get("mode") != "postgresql":
        raise RuntimeError("Production tickets are not using PostgreSQL")
    smoke_token = os.getenv("SMOKE_API_TOKEN", "").strip()
    if not smoke_token:
        raise RuntimeError("SMOKE_API_TOKEN is required for critical promotion checks")
    auth_headers = {"Authorization": f"Bearer {smoke_token}"}
    acceptance, acceptance_body, _ = request(f"{API_URL}/api/operations/acceptance", headers=auth_headers)
    acceptance_payload = json.loads(acceptance_body)
    if acceptance.status != 200 or acceptance_payload.get("status") == "critical":
        raise RuntimeError("Promotion blocked: a critical production acceptance check failed")
    billing, billing_body, _ = request(f"{API_URL}/api/operations/billing-certification", headers=auth_headers)
    billing_payload = json.loads(billing_body)
    if billing.status != 200 or billing_payload.get("releaseReady") is not True:
        raise RuntimeError("Promotion blocked: billing release certification failed")
    app, html, app_ms = request(APP_URL)
    if app.status != 200 or b"flutter_bootstrap.js" not in html:
        raise RuntimeError("Web application shell is unavailable")

    for route in ("/", "/login", "/signup", "/workspace"):
        page, page_body, _ = request(f"{SITE_URL}{route}")
        if page.status != 200 or len(page_body) < 100:
            raise RuntimeError(f"Customer route is unavailable: {route}")
    manifest, manifest_body, _ = request(f"{APP_URL}/manifest.json")
    if manifest.status != 200 or "workspace" not in manifest_body.decode("utf-8", "replace").lower():
        raise RuntimeError("Workspace PWA manifest is unavailable or has the wrong scope")
    worker, worker_body, _ = request(f"{APP_URL}/flutter_service_worker.js")
    if worker.status != 200 or len(worker_body) < 100:
        raise RuntimeError("Workspace service worker is unavailable")

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

    readiness, body, props_ms, payload, feed_age_minutes = (
        read_fresh_prop_readiness()
    )
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

    bundle, javascript, _ = request(f"{APP_URL}/main.dart.js")
    lowered = javascript.lower()
    if bundle.status != 200 or b"localhost" in lowered or b"127.0.0.1" in lowered:
        raise RuntimeError("Production JavaScript contains a local backend address")
    if b"api.propsintell.com" not in lowered:
        raise RuntimeError("Production API domain is missing from the web bundle")
    for marker in (b"scoreboard", b"track record", b"sign out"):
        if marker not in lowered:
            raise RuntimeError(f"Production bundle is missing feature marker: {marker.decode()}")

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
