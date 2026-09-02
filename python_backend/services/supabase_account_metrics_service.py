"""Owner-only account reporting from the canonical Supabase profile store."""

from __future__ import annotations

from datetime import datetime
import hashlib
import os
from typing import Any

import requests


_PRO_TIERS = {"pro", "edge", "gold", "pro_gold", "pro-gold"}


def _configuration() -> tuple[str, dict[str, str]] | None:
    base_url = os.getenv("SUPABASE_URL", "").strip().rstrip("/")
    service_key = (
        os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
        or os.getenv("SUPABASE_SERVICE_KEY", "").strip()
    )
    if not base_url or not service_key:
        return None
    return (
        f"{base_url}/rest/v1/user_profiles",
        {
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Accept": "application/json",
        },
    )


def supabase_profiles() -> list[dict[str, Any]] | None:
    configured = _configuration()
    if configured is None:
        return None
    url, headers = configured
    response = requests.get(
        url,
        params={"select": "*", "order": "created_at.desc"},
        headers=headers,
        timeout=10,
    )
    response.raise_for_status()
    payload = response.json()
    profiles = [dict(row) for row in payload] if isinstance(payload, list) else []

    try:
        auth_response = requests.get(
            f"{base_url.rsplit('/rest/v1/user_profiles', 1)[0]}/auth/v1/admin/users",
            params={"page": 1, "per_page": 1000},
            headers=headers,
            timeout=10,
        )
        auth_response.raise_for_status()
        auth_payload = auth_response.json()
        auth_users = auth_payload.get("users", []) if isinstance(auth_payload, dict) else []
    except requests.RequestException:
        auth_users = []
    profiles_by_id = {str(row.get("id") or ""): row for row in profiles}
    merged: list[dict[str, Any]] = []
    for raw_user in auth_users:
        if not isinstance(raw_user, dict):
            continue
        user_id = str(raw_user.get("id") or "")
        row = dict(profiles_by_id.pop(user_id, {}))
        metadata = raw_user.get("user_metadata") or {}
        row.setdefault("id", user_id)
        row["email"] = row.get("email") or raw_user.get("email") or ""
        row["username"] = row.get("username") or metadata.get("username") or ""
        row["display_name"] = (
            row.get("display_name")
            or metadata.get("display_name")
            or metadata.get("full_name")
            or ""
        )
        row["created_at"] = row.get("created_at") or raw_user.get("created_at")
        row["updated_at"] = row.get("updated_at") or raw_user.get("updated_at")
        merged.append(row)
    merged.extend(profiles_by_id.values())
    merged.sort(key=lambda row: str(row.get("created_at") or ""), reverse=True)
    return merged


def _instant(value: object) -> datetime | None:
    if value in (None, ""):
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.astimezone()
    except (TypeError, ValueError):
        return None


def supabase_profile_metrics(start: datetime, end: datetime) -> dict[str, object]:
    try:
        rows = supabase_profiles()
    except Exception as exc:
        return {"available": False, "error": type(exc).__name__}
    if rows is None:
        return {"available": False, "error": "not_configured"}
    tiers = [str(row.get("subscription_tier") or "").strip().lower() for row in rows]
    created = [_instant(row.get("created_at")) for row in rows]
    return {
        "available": True,
        "totalUsers": len(rows),
        "newUsers": sum(
            1 for value in created if value is not None and start <= value < end
        ),
        "coreSubscribers": sum(1 for tier in tiers if tier == "core"),
        "proSubscribers": sum(1 for tier in tiers if tier in _PRO_TIERS),
    }


def _profile_row(row: dict[str, Any]) -> dict[str, object]:
    email = str(row.get("email") or "")
    username = str(row.get("username") or "")
    name = str(row.get("display_name") or row.get("full_name") or username or "")
    if not name and "@" in email:
        name = email.split("@", 1)[0]
    return {
        "email": email,
        "userId": row.get("id") or "",
        "username": username,
        "name": name,
        "member": (
            row.get("assigned_member_role")
            or row.get("subscription_tier")
            or "user"
        ),
        "signedUpAt": row.get("created_at"),
        "lastUpdatedAt": row.get("updated_at"),
        "avatarUrl": row.get("avatar_url") or "",
        "source": "Supabase",
    }


def supabase_account_rows(limit: int = 50) -> list[dict[str, object]] | None:
    rows = supabase_profiles()
    if rows is None:
        return None
    return [
        _profile_row(row)
        for row in rows[: max(1, min(int(limit), 250))]
    ]


def enrich_active_user_rows(
    activity: list[dict[str, object]],
) -> list[dict[str, object]]:
    try:
        profiles = supabase_profiles() or []
    except Exception:
        profiles = []
    by_hash: dict[str, dict[str, object]] = {}
    for profile in profiles:
        owner_row = _profile_row(profile)
        for identity in (profile.get("id"), profile.get("email")):
            normalized = str(identity or "").strip()
            if normalized:
                by_hash[hashlib.sha256(normalized.encode("utf-8")).hexdigest()] = owner_row
    enriched: list[dict[str, object]] = []
    for row in activity:
        actor = str(row.get("actor") or "")
        profile = by_hash.get(actor, {})
        enriched.append(
            {
                "email": profile.get("email") or row.get("email") or "",
                "userId": profile.get("userId") or row.get("userId") or actor[:12],
                "username": profile.get("username") or row.get("username") or "",
                "name": profile.get("name") or row.get("name") or "",
                "member": profile.get("member") or row.get("member") or "",
                "requests": row.get("requests") or 0,
                "lastSeenAt": row.get("lastSeenAt"),
            }
        )
    return enriched
