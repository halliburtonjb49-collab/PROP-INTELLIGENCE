import importlib.util
import urllib.error
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "post_deploy_smoke",
    ROOT / "tools" / "post_deploy_smoke.py",
)
assert SPEC is not None and SPEC.loader is not None
post_deploy_smoke = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(post_deploy_smoke)


class _Response:
    status = 200

    def read(self) -> bytes:
        return b"ok"


def _bad_gateway(url: str) -> urllib.error.HTTPError:
    return urllib.error.HTTPError(url, 502, "Bad Gateway", {}, None)


def test_request_recovers_after_extended_render_rollout(monkeypatch) -> None:
    attempts = 0
    delays: list[int] = []

    def fake_urlopen(request, timeout):
        nonlocal attempts
        attempts += 1
        if attempts <= 4:
            raise _bad_gateway(request.full_url)
        return _Response()

    monkeypatch.setattr(post_deploy_smoke.urllib.request, "urlopen", fake_urlopen)
    monkeypatch.setattr(post_deploy_smoke.time, "sleep", delays.append)

    response, body, _ = post_deploy_smoke.request("https://example.com/health")

    assert response.status == 200
    assert body == b"ok"
    assert attempts == 5
    assert delays == [2, 4, 8, 10]


def test_request_does_not_retry_authentication_failures(monkeypatch) -> None:
    attempts = 0

    def fake_urlopen(request, timeout):
        nonlocal attempts
        attempts += 1
        raise urllib.error.HTTPError(
            request.full_url,
            401,
            "Unauthorized",
            {},
            None,
        )

    monkeypatch.setattr(post_deploy_smoke.urllib.request, "urlopen", fake_urlopen)

    try:
        post_deploy_smoke.request("https://example.com/private")
    except urllib.error.HTTPError as exc:
        assert exc.code == 401
    else:
        raise AssertionError("401 response should fail immediately")

    assert attempts == 1
