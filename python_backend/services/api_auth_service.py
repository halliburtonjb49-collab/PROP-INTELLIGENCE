"""Validate Supabase access tokens for private API resources."""
import base64
import hashlib
import json
import os
import time
from dataclasses import dataclass
from enum import IntEnum
from threading import Lock

import requests
from fastapi import Header, HTTPException
from config import HTTP_TIMEOUT_SECONDS

_DEFAULT_OWNER_EMAILS = {
    "propsintell@gmail.com",
}
_DEFAULT_OWNER_USER_IDS = {"7fdb460c-dcaa-42ac-89c1-e9950b9b9c55"}


class AccessLevel(IntEnum):
    FREE = 0
    CORE = 1
    PRO = 2
    ADMIN = 3
    OWNER = 4


@dataclass(frozen=True)
class Membership:
    user_id: str
    level: AccessLevel
    subscription_tier: str
    role: str

    @property
    def has_core_access(self) -> bool:
        return self.level >= AccessLevel.CORE

    @property
    def has_pro_access(self) -> bool:
        return self.level >= AccessLevel.PRO


_MEMBERSHIP_CACHE_TTL_SECONDS = max(
    0.0,
    min(60.0, float(os.getenv("MEMBERSHIP_CACHE_TTL_SECONDS", "30"))),
)
_MEMBERSHIP_CACHE_MAX_ENTRIES = 2048
_membership_cache_lock = Lock()
_membership_cache: dict[str, tuple[float, Membership]] = {}


def clear_membership_cache() -> None:
    """Clear the short-lived access cache (primarily for tests and revocation)."""
    with _membership_cache_lock:
        _membership_cache.clear()


def _membership_cache_key(token: str) -> str:
    # Never retain bearer tokens in process memory longer than the request.
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _cached_membership(token: str) -> Membership | None:
    if _MEMBERSHIP_CACHE_TTL_SECONDS <= 0:
        return None
    key = _membership_cache_key(token)
    now = time.monotonic()
    with _membership_cache_lock:
        cached = _membership_cache.get(key)
        if cached is None:
            return None
        expires_at, membership = cached
        if expires_at <= now:
            _membership_cache.pop(key, None)
            return None
        return membership


def _remember_membership(token: str, membership: Membership) -> Membership:
    if _MEMBERSHIP_CACHE_TTL_SECONDS <= 0:
        return membership
    key = _membership_cache_key(token)
    with _membership_cache_lock:
        if len(_membership_cache) >= _MEMBERSHIP_CACHE_MAX_ENTRIES:
            _membership_cache.clear()
        _membership_cache[key] = (
            time.monotonic() + _MEMBERSHIP_CACHE_TTL_SECONDS,
            membership,
        )
    return membership


def _owner_emails() -> set[str]:
    """Return the immutable production owner email allowlist."""
    configured = {
        email.strip().lower()
        for email in os.getenv("OWNER_EMAILS", "").split(",")
        if email.strip()
    }
    return _DEFAULT_OWNER_EMAILS | configured


def _owner_user_ids() -> set[str]:
    """Return the single immutable production owner user ID."""
    return _DEFAULT_OWNER_USER_IDS


def _token_claims(token: str) -> dict[str, object]:
    """Read identity claims only after Supabase has validated the token."""
    try:
        encoded_payload = token.split(".")[1]
        padding = "=" * (-len(encoded_payload) % 4)
        payload = base64.urlsafe_b64decode(encoded_payload + padding)
        decoded = json.loads(payload)
    except (IndexError, ValueError, TypeError, json.JSONDecodeError):
        return {}
    return decoded if isinstance(decoded, dict) else {}

def _supabase_user(token: str) -> dict[str, object] | None:
    url = os.getenv("SUPABASE_URL", "").rstrip("/")
    anon_key = os.getenv("SUPABASE_ANON_KEY", "").strip()
    if not url or not anon_key or not token:
        return None
    response = requests.get(f"{url}/auth/v1/user", headers={"apikey": anon_key, "Authorization": f"Bearer {token}"}, timeout=HTTP_TIMEOUT_SECONDS)
    if response.status_code != 200:
        return None
    payload = response.json()
    if not isinstance(payload, dict):
        return None

    # Supabase has already authenticated the bearer token above. Some hosted
    # responses omit identity metadata, so fill only missing fields from that
    # same validated token instead of incorrectly downgrading an owner.
    claims = _token_claims(token)
    for key in ("email", "app_metadata", "user_metadata"):
        if payload.get(key) in (None, "", {}):
            payload[key] = claims.get(key)
    return payload


def _supabase_profile(token: str, user_id: str) -> dict[str, object]:
    """Read the authenticated user's trusted subscription row through RLS."""
    url = os.getenv("SUPABASE_URL", "").rstrip("/")
    anon_key = os.getenv("SUPABASE_ANON_KEY", "").strip()
    if not url or not anon_key:
        return {}
    response = requests.get(
        f"{url}/rest/v1/user_profiles",
        params={
            "id": f"eq.{user_id}",
            "select": "subscription_tier,is_premium,assigned_member_role,founder_number",
            "limit": "1",
        },
        headers={
            "apikey": anon_key,
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    if response.status_code != 200:
        raise HTTPException(status_code=503, detail="Membership service unavailable")
    payload = response.json()
    if not isinstance(payload, list) or not payload:
        return {}
    row = payload[0]
    return row if isinstance(row, dict) else {}


def _resolve_membership_uncached(authorization: str) -> Membership:
    """Resolve identity and access from Supabase-verified server-side data."""
    token = authorization.removeprefix("Bearer ").strip()
    try:
        user = _supabase_user(token)
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=503,
            detail="Authentication service unavailable",
        ) from exc
    if not user:
        raise HTTPException(
            status_code=401,
            detail="Valid Supabase access token required",
        )

    user_id = str(user.get("id") or "").strip()
    if not user_id:
        raise HTTPException(
            status_code=401,
            detail="Valid Supabase access token required",
        )
    email = str(user.get("email") or "").strip().lower()
    metadata = user.get("app_metadata") or {}
    role = (
        str(metadata.get("role") or "").strip().lower()
        if isinstance(metadata, dict)
        else ""
    )
    if user_id.lower() in _owner_user_ids() or email in _owner_emails():
        return Membership(user_id, AccessLevel.OWNER, "pro", "owner")
    if role == "admin":
        return Membership(user_id, AccessLevel.ADMIN, "pro", "admin")

    try:
        profile = _supabase_profile(token, user_id)
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=503,
            detail="Membership service unavailable",
        ) from exc
    raw_tier = str(profile.get("subscription_tier") or "free").strip().lower()
    granted_role = str(profile.get("assigned_member_role") or "").strip().lower()
    if granted_role in {"pro", "pro_founder"}:
        return Membership(user_id, AccessLevel.PRO, "pro", granted_role)
    if granted_role == "core" and raw_tier not in {
        "edge", "gold", "pro", "pro_gold", "pro-gold"
    } and profile.get("is_premium") is not True:
        return Membership(user_id, AccessLevel.CORE, "core", granted_role)
    if raw_tier in {"edge", "gold", "pro", "pro_gold", "pro-gold"} or profile.get("is_premium") is True:
        return Membership(user_id, AccessLevel.PRO, raw_tier or "pro", "user")
    if raw_tier == "core":
        return Membership(user_id, AccessLevel.CORE, "core", "user")
    return Membership(user_id, AccessLevel.FREE, "free", "user")


def resolve_membership(authorization: str = Header(default="")) -> Membership:
    """Resolve access once per short session window instead of per API call."""
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        return _resolve_membership_uncached(authorization)
    cached = _cached_membership(token)
    if cached is not None:
        return cached
    return _remember_membership(
        token,
        _resolve_membership_uncached(authorization),
    )


def require_core(authorization: str = Header(default="")) -> Membership:
    membership = resolve_membership(authorization)
    if not membership.has_core_access:
        raise HTTPException(status_code=403, detail="Core membership required")
    return membership


def require_pro(authorization: str = Header(default="")) -> Membership:
    membership = resolve_membership(authorization)
    if not membership.has_pro_access:
        raise HTTPException(status_code=403, detail="Pro membership required")
    return membership

def verify_supabase_token(token: str) -> str | None:
    user = _supabase_user(token)
    return str(user.get("id") or "").strip() or None if user else None

def require_user_id(authorization: str = Header(default="")) -> str:
    token = authorization.removeprefix("Bearer ").strip()
    try:
        user_id = verify_supabase_token(token)
    except requests.RequestException as exc:
        raise HTTPException(status_code=503, detail="Authentication service unavailable") from exc
    if user_id is None:
        raise HTTPException(status_code=401, detail="Valid Supabase access token required")
    return user_id


def require_slip_user_id(authorization: str = Header(default="")) -> str:
    """Resolve the durable ticket owner shared by approved owner identities."""
    membership = resolve_membership(authorization)
    if membership.level >= AccessLevel.OWNER:
        return next(iter(_DEFAULT_OWNER_USER_IDS))
    return membership.user_id


def require_admin(x_admin_key: str = Header(default=""), authorization: str = Header(default="")) -> str:
    expected = os.getenv("ADMIN_API_KEY", "").strip()
    if expected and x_admin_key and __import__("hmac").compare_digest(x_admin_key, expected):
        return "admin"
    token = authorization.removeprefix("Bearer ").strip()
    try:
        user = _supabase_user(token)
    except requests.RequestException as exc:
        raise HTTPException(status_code=503, detail="Authentication service unavailable") from exc
    metadata = (user or {}).get("app_metadata") or {}
    # Only app_metadata is written by trusted server-side administration.
    # Supabase users can edit user_metadata, so it must never grant a
    # privileged role.
    role = str(metadata.get("role") or "").lower() if isinstance(metadata, dict) else ""
    email = str((user or {}).get("email") or "").strip().lower()
    user_id = str((user or {}).get("id") or "").strip().lower()
    if user and (
        role == "admin"
        or email in _owner_emails()
        or user_id in _owner_user_ids()
    ):
        return str(user.get("id"))
    raise HTTPException(status_code=401, detail="Administrator access required")


def require_owner(authorization: str = Header(default="")) -> str:
    token = authorization.removeprefix("Bearer ").strip()
    try:
        user = _supabase_user(token)
    except requests.RequestException as exc:
        raise HTTPException(status_code=503, detail="Authentication service unavailable") from exc
    email = str((user or {}).get("email") or "").strip().lower()
    user_id = str((user or {}).get("id") or "").strip().lower()
    if user and (
        email in _owner_emails()
        or user_id in _owner_user_ids()
    ):
        return str(user.get("id"))
    raise HTTPException(status_code=403, detail="Owner access required")
