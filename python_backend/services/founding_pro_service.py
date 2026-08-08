"""Enforce lifetime Founding Pro capacity and checkout reservations."""

import os

from database.postgres import database_is_configured, get_database_pool


def _positive_int_env(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError:
        return default
    return value if value > 0 else default


def founding_member_limit() -> int:
    return _positive_int_env("FOUNDING_PRO_MEMBER_LIMIT", 100)


def founding_product_ids() -> set[str]:
    return {
        value.strip()
        for value in os.getenv("REVENUECAT_FOUNDING_PRODUCT_IDS", "").split(",")
        if value.strip()
    }


def is_founding_event(event: dict[str, object]) -> bool:
    return str(event.get("product_id") or "").strip() in founding_product_ids()


def reserve_founding_pro_slot(user_id: str) -> dict[str, object]:
    if not user_id:
        return {"available": False, "reason": "Authenticated user required"}
    if not database_is_configured():
        return {"available": False, "reason": "DATABASE_URL is not configured"}
    limit = founding_member_limit()
    minutes = _positive_int_env("FOUNDING_PRO_RESERVATION_MINUTES", 30)
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("select pg_advisory_xact_lock(hashtext('founding_pro_capacity'))")
        cursor.execute(
            """select status, reservation_expires_at > now()
            from founding_pro_claims where user_id = %s""",
            (user_id,),
        )
        existing = cursor.fetchone()
        if existing and existing[0] == "active":
            connection.commit()
            return {"available": True, "alreadyClaimed": True, "limit": limit}
        if existing and existing[0] == "released":
            connection.commit()
            return {
                "available": False,
                "reason": "Founding membership must remain continuously active",
                "limit": limit,
            }
        if existing and existing[0] == "reserved" and existing[1]:
            connection.commit()
            return {"available": True, "reserved": True, "limit": limit}
        cursor.execute(
            """delete from founding_pro_claims
            where status = 'reserved' and reservation_expires_at <= now()"""
        )
        cursor.execute(
            """select count(*) from founding_pro_claims
            where claimed_at is not null
               or (status = 'reserved' and reservation_expires_at > now())"""
        )
        used = int(cursor.fetchone()[0])
        if used >= limit:
            connection.commit()
            return {
                "available": False,
                "soldOut": True,
                "remaining": 0,
                "limit": limit,
            }
        cursor.execute(
            """insert into founding_pro_claims(
                user_id,status,reserved_at,reservation_expires_at,updated_at)
            values(%s,'reserved',now(),now() + (%s * interval '1 minute'),now())
            on conflict(user_id) do update set
              status='reserved', reserved_at=now(),
              reservation_expires_at=now() + (%s * interval '1 minute'),
              claimed_at=null, released_at=null, product_id=null, updated_at=now()""",
            (user_id, minutes, minutes),
        )
        connection.commit()
    return {
        "available": True,
        "reserved": True,
        "remaining": limit - used - 1,
        "limit": limit,
    }


def apply_founding_event(
    cursor: object,
    event: dict[str, object],
    user_id: str,
) -> dict[str, object] | None:
    event_type = str(event.get("type") or "").upper()
    product_id = str(event.get("product_id") or "").strip()
    founding = is_founding_event(event)
    if not founding and (event_type != "PRODUCT_CHANGE" or not product_id):
        return None

    cursor.execute("select pg_advisory_xact_lock(hashtext('founding_pro_capacity'))")
    if founding and event_type == "EXPIRATION":
        cursor.execute(
            """update founding_pro_claims set status='released', released_at=now(),
            reservation_expires_at=null, updated_at=now()
            where user_id=%s and status='active'""",
            (user_id,),
        )
        return None
    if event_type == "PRODUCT_CHANGE" and not founding:
        cursor.execute(
            """update founding_pro_claims set status='released', released_at=now(),
            reservation_expires_at=null, updated_at=now()
            where user_id=%s and status='active'""",
            (user_id,),
        )
        return None

    cursor.execute(
        "select status from founding_pro_claims where user_id=%s",
        (user_id,),
    )
    claim = cursor.fetchone()
    if claim and claim[0] == "released":
        return {
            "updated": False,
            "foundingRejected": True,
            "reason": "Founding membership was not continuously active",
            "tier": "free",
            "userId": user_id,
        }
    if not claim:
        cursor.execute(
            """select count(*) from founding_pro_claims
            where claimed_at is not null
               or (status = 'reserved' and reservation_expires_at > now())"""
        )
        if int(cursor.fetchone()[0]) >= founding_member_limit():
            return {
                "updated": False,
                "foundingRejected": True,
                "reason": "Founding Pro is sold out",
                "tier": "free",
                "userId": user_id,
            }
    cursor.execute(
        """insert into founding_pro_claims(
            user_id,status,claimed_at,product_id,updated_at)
        values(%s,'active',now(),%s,now())
        on conflict(user_id) do update set
          status='active',
          claimed_at=coalesce(founding_pro_claims.claimed_at,now()),
          reservation_expires_at=null, released_at=null,
          product_id=excluded.product_id, updated_at=now()""",
        (user_id, product_id),
    )
    return None
