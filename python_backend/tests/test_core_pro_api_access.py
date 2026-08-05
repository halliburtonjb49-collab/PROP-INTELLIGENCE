from dataclasses import dataclass

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import main
from services import api_auth_service
from services.api_auth_service import (
    AccessLevel,
    Membership,
    require_core,
    require_pro,
)


@dataclass
class SensitiveProp:
    id: str = "secure-prop"
    player: str = "Secure Player"
    sport: str = "NBA"
    matchup: str = "Away @ Home"
    sportsbook: str = "PRIZEPICKS"
    category: str = "POINTS"
    market: str = "Points"
    line: float = 24.5
    startTimeUtc: str = "2099-07-20T20:00:00Z"
    lastUpdatedUtc: str = "2026-07-29T16:00:00Z"
    recommendedSide: str = "OVER"
    pick: str = "OVER"
    pickText: str = "Suggested OVER"
    confidence: int = 86
    edge: float = 7.4
    edgeSigned: float = 7.4
    recommendationEdge: float = 7.4
    evPercentage: float = 9.2
    fairProbability: float = 0.59
    isPositiveEv: bool = True
    projection: float = 27.1
    modelProbability: float = 0.61
    marketProbability: float = 0.52
    recommendationAvailable: bool = True
    tier: str = "A"

    def model_dump(self) -> dict[str, object]:
        return self.__dict__.copy()


CORE = Membership("core-user", AccessLevel.CORE, "core", "user")
PRO = Membership("pro-user", AccessLevel.PRO, "pro", "user")

RESTRICTED_FIELDS = {
    "recommendedSide",
    "pick",
    "pickText",
    "edge",
    "edgeSigned",
    "recommendationEdge",
    "evPercentage",
    "fairProbability",
    "isPositiveEv",
    "projection",
    "projectionSource",
    "projectionModelVersion",
    "projectionSampleSize",
    "projectionVolatility",
    "projectionCalibrated",
    "projectionLabel",
    "modelProbability",
    "marketProbability",
    "noVigOverProbability",
    "noVigUnderProbability",
    "fairDecimalOdds",
    "probabilityMethod",
    "probabilityMarketWeight",
    "probabilityUncertainty",
    "probabilityCalibrationAdjustment",
    "probabilityCalibrationSampleSize",
    "recommendationAvailable",
    "recommendationUnavailableReason",
    "tier",
    "fatigueIndex",
    "fatigueMultiplier",
    "paceMultiplier",
    "opponentDefenseMultiplier",
    "usageMultiplier",
    "homeAwayMultiplier",
    "matchupContext",
    "matchupMultiplier",
    "officiatingContext",
    "officiatingAdjustment",
    "sentimentLabel",
    "sentimentScore",
    "sentimentSampleSize",
}


def _deny_core() -> Membership:
    raise HTTPException(status_code=403, detail="Pro membership required")


def test_core_props_contain_facts_and_no_proprietary_fields(monkeypatch) -> None:
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [SensitiveProp()])
    main.app.dependency_overrides[require_core] = lambda: CORE
    response = TestClient(main.app).get("/api/props?includeStale=true")

    assert response.status_code == 200
    payload = response.json()
    row = payload["props"][0]
    assert row["player"] == "Secure Player"
    assert row["line"] == 24.5
    assert row["sportsbook"] == "PRIZEPICKS"
    assert row["confidence"] == 86
    assert RESTRICTED_FIELDS.isdisjoint(row)
    assert payload["recommendationCoverage"] == {"total": 1}
    assert response.headers["cache-control"].startswith("private")
    assert "Authorization" in response.headers["vary"]


def test_pro_props_retain_proprietary_fields(monkeypatch) -> None:
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: [SensitiveProp()])
    main.app.dependency_overrides[require_core] = lambda: PRO
    row = TestClient(main.app).get(
        "/api/props?includeStale=true"
    ).json()["props"][0]
    assert row["recommendedSide"] == "OVER"
    assert row["confidence"] == 86
    assert row["edge"] == 7.4
    assert row["evPercentage"] == 9.2
    assert row["projection"] == 27.1


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "/api/props/ev"),
        ("get", "/api/prop-alerts"),
        ("get", "/api/props/calibration"),
        ("get", "/api/props-test"),
        ("get", "/api/intelligence/capabilities"),
        ("get", "/api/intelligence/calibration"),
        ("get", "/api/intelligence/performance"),
        ("post", "/api/intelligence/correlations"),
        ("post", "/api/intelligence/game-script"),
        ("post", "/api/intelligence/similarity"),
        ("post", "/api/intelligence/sentiment"),
        ("post", "/api/intelligence/predictions"),
        ("post", "/api/intelligence/alerts/evaluate"),
    ],
)
def test_core_is_denied_pro_endpoints(method: str, path: str) -> None:
    main.app.dependency_overrides[require_pro] = _deny_core
    client = TestClient(main.app)
    response = (
        client.get(path)
        if method == "get"
        else client.post(path, json={})
    )
    assert response.status_code == 403


@pytest.mark.parametrize(
    ("profile", "expected"),
    [
        ({"subscription_tier": "free"}, AccessLevel.FREE),
        ({"subscription_tier": "core"}, AccessLevel.CORE),
        ({"subscription_tier": "edge"}, AccessLevel.PRO),
        ({"subscription_tier": "pro"}, AccessLevel.PRO),
    ],
)
def test_membership_resolver_uses_verified_profile(
    monkeypatch, profile: dict[str, object], expected: AccessLevel
) -> None:
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_user",
        lambda _token: {
            "id": "member-id",
            "email": "member@example.com",
            "app_metadata": {},
        },
    )
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_profile",
        lambda _token, _user_id: profile,
    )
    assert api_auth_service.resolve_membership("Bearer verified").level == expected


@pytest.mark.parametrize(
    ("role", "expected"),
    [("admin", AccessLevel.ADMIN), ("owner", AccessLevel.OWNER)],
)
def test_membership_resolver_honors_verified_privileged_roles(
    monkeypatch, role: str, expected: AccessLevel
) -> None:
    monkeypatch.setattr(
        api_auth_service,
        "_supabase_user",
        lambda _token: {
            "id": "privileged-id",
            "email": "privileged@example.com",
            "app_metadata": {"role": role},
        },
    )
    assert api_auth_service.resolve_membership("Bearer verified").level == expected


def test_require_core_rejects_free_and_require_pro_rejects_core(
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        api_auth_service,
        "resolve_membership",
        lambda _authorization: Membership(
            "free-user", AccessLevel.FREE, "free", "user"
        ),
    )
    with pytest.raises(HTTPException) as free_error:
        api_auth_service.require_core("Bearer verified")
    assert free_error.value.status_code == 403

    monkeypatch.setattr(
        api_auth_service,
        "resolve_membership",
        lambda _authorization: CORE,
    )
    with pytest.raises(HTTPException) as core_error:
        api_auth_service.require_pro("Bearer verified")
    assert core_error.value.status_code == 403
