"""Validate Supabase access tokens for private API resources."""
import os
import requests
from fastapi import Header, HTTPException
from config import HTTP_TIMEOUT_SECONDS

def verify_supabase_token(token: str) -> str | None:
    url = os.getenv("SUPABASE_URL", "").rstrip("/")
    anon_key = os.getenv("SUPABASE_ANON_KEY", "").strip()
    if not url or not anon_key or not token:
        return None
    response = requests.get(f"{url}/auth/v1/user", headers={"apikey": anon_key, "Authorization": f"Bearer {token}"}, timeout=HTTP_TIMEOUT_SECONDS)
    if response.status_code != 200:
        return None
    return str(response.json().get("id") or "").strip() or None

def require_user_id(authorization: str = Header(default="")) -> str:
    token = authorization.removeprefix("Bearer ").strip()
    try:
        user_id = verify_supabase_token(token)
    except requests.RequestException as exc:
        raise HTTPException(status_code=503, detail="Authentication service unavailable") from exc
    if user_id is None:
        raise HTTPException(status_code=401, detail="Valid Supabase access token required")
    return user_id


def require_admin(x_admin_key: str = Header(default="")) -> str:
    expected = os.getenv("ADMIN_API_KEY", "").strip()
    if not expected:
        raise HTTPException(status_code=503, detail="Administrative API is not configured")
    if not x_admin_key or not __import__("hmac").compare_digest(x_admin_key, expected):
        raise HTTPException(status_code=401, detail="Valid administrative key required")
    return "admin"
