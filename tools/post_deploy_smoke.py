import json
import sys
import time
import urllib.request


APP_URL = "https://app.propsintell.com"
API_URL = "https://api.propsintell.com"


def request(url: str, *, method: str = "GET", headers: dict[str, str] | None = None):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    started = time.perf_counter()
    response = urllib.request.urlopen(req, timeout=20)
    body = response.read()
    return response, body, (time.perf_counter() - started) * 1000


def main() -> int:
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
                "appMs": round(app_ms),
                "propsMs": round(props_ms),
                "payloadBytes": len(body),
                "props": len(payload["props"]),
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
