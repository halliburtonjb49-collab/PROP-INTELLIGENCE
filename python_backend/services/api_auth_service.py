"""Validate Supabase access tokens for private API resources."""
import base64
import json
import os
import requests
from fastapi import Header, HTTPException
from config import HTTP_TIMEOUT_SECONDS

_DEFAULT_OWNER_EMAILS = {"halliburtonjb49@gmail.com"}


def _owner_emails() -> set[str]:
    configured = {
        value.strip().lower()
        for value in os.getenv("OWNER_EMAILS", "").split(",")
        if value.strip()
    }
    return _DEFAULT_OWNER_EMAILS | configured


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
    user_metadata = (user or {}).get("user_metadata") or {}
    role = str(metadata.get("role") or user_metadata.get("role") or "").lower() if isinstance(metadata, dict) and isinstance(user_metadata, dict) else ""
    email = str((user or {}).get("email") or "").strip().lower()
    if user and (role in {"owner", "admin"} or email in _owner_emails()):
        return str(user.get("id"))
    raise HTTPException(status_code=401, detail="Administrator access required")


def require_owner(authorization: str = Header(default="")) -> str:
    token = authorization.removeprefix("Bearer ").strip()
    try:
        user = _supabase_user(token)
    except requests.RequestException as exc:
        raise HTTPException(status_code=503, detail="Authentication service unavailable") from exc
    metadata = (user or {}).get("app_metadata") or {}
    user_metadata = (user or {}).get("user_metadata") or {}
    role = str(metadata.get("role") or user_metadata.get("role") or "").lower() if isinstance(metadata, dict) and isinstance(user_metadata, dict) else ""
    email = str((user or {}).get("email") or "").strip().lower()
    if user and (role == "owner" or email in _owner_emails()):
        return str(user.get("id"))
    raise HTTPException(status_code=403, detail="Owner access required")
