"""Canonical PI identity, media, reconciliation, and inventory registry."""
from __future__ import annotations

import hashlib, json, logging, re, unicodedata
from collections import Counter
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Any, Iterable
from urllib.request import Request, urlopen
from database.postgres import database_is_configured, get_database_pool

LOGGER = logging.getLogger(__name__)
_LOCK = Lock()
_MEDIA_CACHE: dict[tuple[str, str, str], tuple[datetime, str]] = {}
_MEDIA_CACHE_TTL = timedelta(minutes=10)

def normalize_identity(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value or "")
    ascii_value = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return " ".join(re.sub(r"[^a-z0-9]+", " ", ascii_value.lower()).split())

def stable_identity_id(*, identity_type: str, sport: str, name: str) -> str:
    """Return the same opaque PI identity across providers and refreshes."""
    normalized = normalize_identity(name)
    digest = hashlib.sha256(
        f"{identity_type.lower()}|{sport.upper()}|{normalized}".encode("utf-8")
    ).hexdigest()[:20]
    return f"pi_{identity_type.lower()}_{digest}"

def _value(row: object, *names: str) -> Any:
    for name in names:
        value = row.get(name) if isinstance(row, dict) else getattr(row, name, None)
        if value not in (None, ""): return value
    return None

def _media_is_valid(url: str) -> bool:
    if not url or not url.lower().startswith(("https://", "http://")): return False
    try:
        with urlopen(Request(url, method="HEAD", headers={"User-Agent": "PI-Media-Registry/1.0"}), timeout=4) as response:
            return response.status < 400 and str(response.headers.get("content-type") or "").lower().startswith("image/")
    except Exception: return False

def registered_media_url(
    *,
    identity_type: str,
    sport: str,
    name: str,
    allow_database_lookup: bool = False,
) -> str:
    """Return registered media without blocking live prop responses.

    Player-image resolution runs while the shared prop catalog is hydrated.
    A database lookup for every cache miss made the first mobile request wait
    minutes when the registry pool was busy. Live callers now use memory only
    and immediately fall through to the league image providers. Maintenance
    callers may explicitly opt into a database lookup.
    """
    normalized = normalize_identity(name); key = (identity_type, sport.upper(), normalized); now = datetime.now(timezone.utc)
    cached = _MEDIA_CACHE.get(key)
    if cached and now - cached[0] < _MEDIA_CACHE_TTL: return cached[1]
    if not allow_database_lookup or not normalized or not database_is_configured(): return ""
    try:
        with get_database_pool().connection(timeout=2) as connection, connection.cursor() as cursor:
            cursor.execute("""select coalesce(nullif(m.cached_url,''),m.source_url) from pi_identities i
              join pi_identity_media m on m.pi_identity_id=i.id where i.identity_type=%s and i.sport=%s
              and i.normalized_name=%s and m.is_last_known_good and m.status='approved'
              order by m.last_verified_at desc nulls last limit 1""", (identity_type, sport.upper(), normalized))
            row = cursor.fetchone()
        result = str(row[0] or "") if row else ""; _MEDIA_CACHE[key] = (now, result); return result
    except Exception: return ""

def promote_media_candidate(*, identity_type: str, sport: str, name: str, provider: str, url: str) -> bool:
    normalized = normalize_identity(name)
    if not normalized or not database_is_configured() or not _media_is_valid(url): return False
    media_type = "logo" if identity_type == "team" else "headshot"
    with _LOCK:
        try:
            with get_database_pool().connection(timeout=5) as connection, connection.cursor() as cursor:
                cursor.execute("""insert into pi_identities(identity_type,sport,canonical_name,normalized_name) values(%s,%s,%s,%s)
                  on conflict(identity_type,sport,normalized_name) do update set canonical_name=excluded.canonical_name,updated_at=now() returning id""",
                  (identity_type, sport.upper(), name.strip(), normalized)); identity_id = cursor.fetchone()[0]
                cursor.execute("update pi_identity_media set is_last_known_good=false,updated_at=now() where pi_identity_id=%s and media_type=%s and is_last_known_good", (identity_id, media_type))
                cursor.execute("""insert into pi_identity_media(pi_identity_id,media_type,source_provider,source_url,content_hash,status,is_last_known_good,last_verified_at)
                  values(%s,%s,%s,%s,%s,'approved',true,now()) on conflict(pi_identity_id,media_type,source_provider,source_url)
                  do update set status='approved',is_last_known_good=true,last_verified_at=now(),failure_count=0,updated_at=now()""",
                  (identity_id, media_type, provider, url, hashlib.sha256(url.encode()).hexdigest())); connection.commit()
            _MEDIA_CACHE[(identity_type, sport.upper(), normalized)] = (
                datetime.now(timezone.utc),
                url,
            )
            return True
        except Exception as exc: LOGGER.warning("Media registry promotion failed: %s", exc); return False

def reconcile_catalog(rows: Iterable[object], *, provider: str = "live-catalog") -> dict[str, object]:
    items = list(rows)
    counts = Counter()
    unresolved_rows: dict[tuple[str, str, str, str], tuple[object, ...]] = {}
    identities: dict[tuple[str, str, str, str], tuple[str, str, str, str]] = {}

    for raw in items:
        sport = str(_value(raw, "sport") or "UNKNOWN").upper()
        player = str(_value(raw, "player") or "").strip()
        source_id = str(
            _value(raw, "sourcePlayerId", "source_player_id", "playerId") or ""
        ).strip()
        source_provider = str(
            _value(raw, "sourceProvider", "provider", "bookmaker") or provider
        ).lower()
        normalized = normalize_identity(player)
        counts[(source_provider, sport)] += 1
        if not normalized:
            key = (sport, source_provider, source_id, player)
            unresolved_rows.setdefault(
                key,
                (
                    sport,
                    source_provider,
                    source_id,
                    player,
                    normalized,
                    json.dumps({"propId": _value(raw, "id")}),
                ),
            )
            continue
        identities.setdefault(
            (sport, normalized, source_provider, source_id),
            (sport, player, normalized, source_provider, source_id),
        )

    if not database_is_configured():
        return {
            "status": "unavailable",
            "reason": "database_not_configured",
            "rows": len(items),
        }

    try:
        with get_database_pool().connection(timeout=2) as connection, connection.cursor() as cursor:
            cursor.execute("set local lock_timeout = '1000ms'")
            cursor.execute("set local statement_timeout = '5000ms'")
            for values in unresolved_rows.values():
                cursor.execute(
                    """insert into pi_identity_reconciliation_queue(identity_type,sport,provider,provider_identity_id,observed_name,normalized_name,reason,sample_payload)
                      values('player',%s,%s,%s,%s,%s,'missing_name',%s::jsonb) on conflict(identity_type,sport,provider,provider_identity_id,normalized_name,reason)
                      do update set occurrence_count=pi_identity_reconciliation_queue.occurrence_count+1,last_seen_at=now(),sample_payload=excluded.sample_payload""",
                    values,
                )
            for sport, player, normalized, source_provider, source_id in identities.values():
                cursor.execute(
                    """insert into pi_identities(identity_type,sport,canonical_name,normalized_name)
                      values('player',%s,%s,%s)
                      on conflict(identity_type,sport,normalized_name) do nothing
                      returning id""",
                    (sport, player, normalized),
                )
                identity = cursor.fetchone()
                if identity is None:
                    cursor.execute(
                        """select id from pi_identities
                          where identity_type='player' and sport=%s and normalized_name=%s
                          limit 1""",
                        (sport, normalized),
                    )
                    identity = cursor.fetchone()
                if identity is None:
                    continue
                cursor.execute(
                    """insert into pi_identity_aliases(pi_identity_id,provider,provider_identity_id,alias,normalized_alias,last_seen_at)
                      values(%s,%s,%s,%s,%s,now()) on conflict(provider,provider_identity_id,normalized_alias)
                      do update set pi_identity_id=excluded.pi_identity_id,alias=excluded.alias,last_seen_at=now()""",
                    (identity[0], source_provider, source_id, player, normalized),
                )
            for (source_provider, sport), prop_count in counts.items():
                cursor.execute(
                    "select prop_count from pi_provider_inventory_observations where provider=%s and sport=%s order by observed_at desc limit 1",
                    (source_provider, sport),
                )
                prior = cursor.fetchone()
                previous = int(prior[0]) if prior else None
                ratio = ((prop_count - previous) / previous) if previous else None
                status = (
                    "interrupted" if previous and prop_count == 0
                    else "critical" if ratio is not None and ratio <= -.65
                    else "warning" if ratio is not None and ratio <= -.35
                    else "healthy"
                )
                cursor.execute(
                    "insert into pi_provider_inventory_observations(provider,sport,prop_count,prior_prop_count,change_ratio,status) values(%s,%s,%s,%s,%s,%s)",
                    (source_provider, sport, prop_count, previous, ratio, status),
                )
            connection.commit()
        return {
            "status": "complete",
            "rows": len(items),
            "identitiesObserved": len(items) - len(unresolved_rows),
            "uniqueIdentitiesWritten": len(identities),
            "unresolved": len(unresolved_rows),
            "segments": len(counts),
        }
    except Exception as exc:
        LOGGER.warning(
            "Identity registry reconciliation failed: %s", exc, exc_info=True
        )
        return {
            "status": "unavailable",
            "reason": type(exc).__name__,
            "rows": len(items),
        }

def registry_summary() -> dict[str, object]:
    if not database_is_configured(): return {"status":"unavailable","reason":"database_not_configured"}
    try:
        with get_database_pool().connection(timeout=4) as connection, connection.cursor() as cursor:
            cursor.execute("select identity_type,count(*) from pi_identities group by identity_type"); identities={str(r[0]):int(r[1]) for r in cursor.fetchall()}
            cursor.execute("select count(*) from pi_identity_media where is_last_known_good and status='approved'"); media=int(cursor.fetchone()[0])
            cursor.execute("select count(*) from pi_identity_reconciliation_queue where resolved_at is null"); unresolved=int(cursor.fetchone()[0])
            cursor.execute("""select provider,sport,prop_count,prior_prop_count,change_ratio,status,observed_at from pi_provider_inventory_observations order by observed_at desc limit 100""")
            inventory=[{"provider":r[0],"sport":r[1],"propCount":r[2],"priorPropCount":r[3],"changeRatio":float(r[4]) if r[4] is not None else None,"status":r[5],"observedAt":r[6].isoformat() if r[6] else None} for r in cursor.fetchall()]
            cursor.execute("""select id,identity_type,sport,provider,provider_identity_id,observed_name,reason,occurrence_count,last_seen_at from pi_identity_reconciliation_queue where resolved_at is null order by last_seen_at desc limit 100""")
            queue=[{"id":r[0],"identityType":r[1],"sport":r[2],"provider":r[3],"providerIdentityId":r[4],"observedName":r[5],"reason":r[6],"occurrences":r[7],"lastSeenAt":r[8].isoformat() if r[8] else None} for r in cursor.fetchall()]
        return {"status":"healthy","identities":identities,"approvedMedia":media,"unresolved":unresolved,"inventory":inventory,"queue":queue}
    except Exception as exc: return {"status":"unavailable","reason":type(exc).__name__}
