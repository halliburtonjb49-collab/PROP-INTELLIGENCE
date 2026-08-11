"""Durable, reversible Owner controls for props and operational alerts."""

from __future__ import annotations

from datetime import datetime, timezone
from hashlib import sha256
import json
from threading import Lock
import time
from typing import Mapping

from database.postgres import database_is_configured, get_database_pool


_CACHE_SECONDS = 20.0
_cache_lock = Lock()
_cached_keys: frozenset[str] = frozenset()
_cached_at = 0.0


def _normalized(value: object) -> str:
    return " ".join(str(value or "").strip().lower().split())


def prop_control_key(*, sport: object, game_id: object, player: object,
                     market: object, provider: object) -> str:
    raw = "|".join(_normalized(value) for value in (
        sport, game_id, player, market, provider,
    ))
    return sha256(raw.encode("utf-8")).hexdigest()[:32]


def prop_control_key_for(prop: object) -> str:
    def value(name: str, fallback: str = "") -> object:
        if isinstance(prop, Mapping):
            return prop.get(name, prop.get(fallback, ""))
        return getattr(prop, name, getattr(prop, fallback, ""))
    return prop_control_key(
        sport=value("sport"), game_id=value("gameId", "eventId"),
        player=value("player"), market=value("market"),
        provider=value("sportsbook", "sourceProvider"),
    )


def _ensure_tables(cursor: object) -> None:
    cursor.execute("""
        create table if not exists owner_prop_quarantines (
            target_key text primary key,
            snapshot jsonb not null default '{}'::jsonb,
            reason text not null,
            actor_user_id text not null,
            quarantined_at timestamptz not null default now(),
            updated_at timestamptz not null default now()
        )
    """)
    cursor.execute("""
        create table if not exists owner_alert_acknowledgements (
            alert_key text primary key,
            acknowledged_count integer not null,
            reason text not null,
            actor_user_id text not null,
            acknowledged_at timestamptz not null default now()
        )
    """)
    cursor.execute("""
        create table if not exists owner_operations_audit (
            id bigserial primary key,
            action text not null,
            target_type text not null,
            target_key text not null,
            reason text not null,
            actor_user_id text not null,
            details jsonb not null default '{}'::jsonb,
            created_at timestamptz not null default now()
        )
    """)
    cursor.execute("""
        create index if not exists owner_operations_audit_target_idx
        on owner_operations_audit(target_type, target_key, created_at desc)
    """)


def _require_database() -> None:
    if not database_is_configured():
        raise RuntimeError("Owner action storage is unavailable")


def active_prop_quarantine_keys(*, force: bool = False) -> frozenset[str]:
    global _cached_at, _cached_keys
    now = time.monotonic()
    with _cache_lock:
        if not force and now - _cached_at < _CACHE_SECONDS:
            return _cached_keys
    if not database_is_configured():
        return frozenset()
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute("select target_key from owner_prop_quarantines")
            keys = frozenset(str(row[0]) for row in cursor.fetchall())
    except Exception:
        return frozenset()
    with _cache_lock:
        _cached_keys, _cached_at = keys, now
    return keys


def filter_owner_quarantined_props(props: list[object]) -> list[object]:
    keys = active_prop_quarantine_keys()
    if not keys:
        return props
    return [prop for prop in props if prop_control_key_for(prop) not in keys]


def set_prop_quarantine(*, target_key: str, quarantined: bool, reason: str,
                        actor_user_id: str, snapshot: Mapping[str, object]) -> dict[str, object]:
    _require_database()
    clean_reason = " ".join(reason.strip().split())
    if len(clean_reason) < 5:
        raise ValueError("A reason of at least 5 characters is required")
    if prop_control_key(
        sport=snapshot.get("sport"), game_id=snapshot.get("gameId"),
        player=snapshot.get("player"), market=snapshot.get("market"),
        provider=snapshot.get("provider"),
    ) != target_key:
        raise ValueError("Prop control key does not match the current inventory item")
    action = "QUARANTINE_PROP" if quarantined else "RESTORE_PROP"
    details = json.dumps(dict(snapshot), default=str)
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        _ensure_tables(cursor)
        if quarantined:
            cursor.execute("""
                insert into owner_prop_quarantines
                    (target_key, snapshot, reason, actor_user_id)
                values (%s, %s::jsonb, %s, %s)
                on conflict(target_key) do update set
                    snapshot=excluded.snapshot, reason=excluded.reason,
                    actor_user_id=excluded.actor_user_id,
                    updated_at=now()
            """, (target_key, details, clean_reason, actor_user_id))
        else:
            cursor.execute(
                "delete from owner_prop_quarantines where target_key=%s",
                (target_key,),
            )
        cursor.execute("""
            insert into owner_operations_audit
                (action, target_type, target_key, reason, actor_user_id, details)
            values (%s, 'PROP', %s, %s, %s, %s::jsonb)
        """, (action, target_key, clean_reason, actor_user_id, details))
        connection.commit()
    active_prop_quarantine_keys(force=True)
    return {"ok": True, "action": action, "targetKey": target_key,
            "quarantined": quarantined}


def set_alert_acknowledgement(*, alert_key: str, count: int, acknowledged: bool,
                              reason: str, actor_user_id: str) -> dict[str, object]:
    _require_database()
    clean_reason = " ".join(reason.strip().split())
    if len(clean_reason) < 5:
        raise ValueError("A reason of at least 5 characters is required")
    action = "ACKNOWLEDGE_ALERT" if acknowledged else "REOPEN_ALERT"
    details = json.dumps({"count": max(0, int(count))})
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        _ensure_tables(cursor)
        if acknowledged:
            cursor.execute("""
                insert into owner_alert_acknowledgements
                    (alert_key, acknowledged_count, reason, actor_user_id)
                values (%s, %s, %s, %s)
                on conflict(alert_key) do update set
                    acknowledged_count=excluded.acknowledged_count,
                    reason=excluded.reason, actor_user_id=excluded.actor_user_id,
                    acknowledged_at=now()
            """, (alert_key, max(0, int(count)), clean_reason, actor_user_id))
        else:
            cursor.execute(
                "delete from owner_alert_acknowledgements where alert_key=%s",
                (alert_key,),
            )
        cursor.execute("""
            insert into owner_operations_audit
                (action, target_type, target_key, reason, actor_user_id, details)
            values (%s, 'ALERT', %s, %s, %s, %s::jsonb)
        """, (action, alert_key, clean_reason, actor_user_id, details))
        connection.commit()
    return {"ok": True, "action": action, "alertKey": alert_key,
            "acknowledged": acknowledged}


def owner_action_snapshot(*, history_limit: int = 40) -> dict[str, object]:
    if not database_is_configured():
        return {"available": False, "quarantines": {}, "acknowledgements": {}, "history": []}
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            _ensure_tables(cursor)
            cursor.execute("select target_key, reason, actor_user_id, quarantined_at from owner_prop_quarantines")
            quarantines = {str(row[0]): {"reason": row[1], "actorUserId": row[2],
                "at": row[3].astimezone(timezone.utc).isoformat()} for row in cursor.fetchall()}
            cursor.execute("select alert_key, acknowledged_count, reason, actor_user_id, acknowledged_at from owner_alert_acknowledgements")
            acknowledgements = {str(row[0]): {"count": int(row[1]), "reason": row[2],
                "actorUserId": row[3], "at": row[4].astimezone(timezone.utc).isoformat()} for row in cursor.fetchall()}
            cursor.execute("""
                select action, target_type, target_key, reason, actor_user_id, details, created_at
                from owner_operations_audit order by created_at desc limit %s
            """, (max(1, min(history_limit, 200)),))
            history = [{"action": row[0], "targetType": row[1], "targetKey": row[2],
                "reason": row[3], "actorUserId": row[4], "details": row[5] or {},
                "createdAt": row[6].astimezone(timezone.utc).isoformat()} for row in cursor.fetchall()]
        return {"available": True, "quarantines": quarantines,
                "acknowledgements": acknowledgements, "history": history}
    except Exception as exc:
        return {"available": False, "error": type(exc).__name__,
                "quarantines": {}, "acknowledgements": {}, "history": []}
