import json
import re
import unicodedata
from functools import lru_cache
from pathlib import Path
from typing import Any

BASE_DIR = Path(__file__).resolve().parent.parent
IDENTITY_MAP_PATH = BASE_DIR / "data" / "player_identity_map.json"


def _normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_only = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    cleaned = re.sub(r"[^a-z0-9]+", " ", ascii_only.lower()).strip()
    return " ".join(cleaned.split())


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


@lru_cache(maxsize=1)
def _load_identity_map() -> dict[str, Any]:
    if not IDENTITY_MAP_PATH.exists():
        return {"providers": {}}
    try:
        payload = json.loads(IDENTITY_MAP_PATH.read_text(encoding="utf-8"))
        if isinstance(payload, dict):
            return payload
    except Exception:
        pass
    return {"providers": {}}


def load_identity_map() -> dict[str, Any]:
    payload = _load_identity_map()
    providers = payload.get("providers")
    if not isinstance(providers, dict):
        payload["providers"] = {}
    return payload


def save_identity_map(payload: dict[str, Any]) -> None:
    IDENTITY_MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    IDENTITY_MAP_PATH.write_text(
        json.dumps(payload, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    _load_identity_map.cache_clear()


def upsert_identity_entry(
    *,
    source_provider: str,
    source_player_id: str,
    canonical_player_id: str,
    full_name: str,
    aliases: list[str] | None = None,
) -> dict[str, Any]:
    provider_key = source_provider.strip().lower()
    source_id = source_player_id.strip()
    canonical = canonical_player_id.strip()
    if not provider_key:
        raise ValueError("source_provider is required")
    if not source_id:
        raise ValueError("source_player_id is required")
    if not canonical:
        raise ValueError("canonical_player_id is required")

    payload = load_identity_map()
    providers = payload.setdefault("providers", {})
    provider_map = providers.setdefault(provider_key, {})
    provider_map[source_id] = {
        "canonical_player_id": canonical,
        "full_name": full_name.strip(),
        "aliases": [value.strip() for value in (aliases or []) if value.strip()],
    }
    save_identity_map(payload)
    return provider_map[source_id]


def bootstrap_identity_candidates(
    *,
    source_provider: str,
    prop_rows: list[dict[str, Any]],
) -> dict[str, Any]:
    provider_key = source_provider.strip().lower()
    payload = load_identity_map()
    providers = payload.setdefault("providers", {})
    provider_map = providers.setdefault(provider_key, {})

    added = 0
    unresolved_names: set[str] = set()

    for row in prop_rows:
        source_id = str(row.get("sourcePlayerId") or row.get("source_player_id") or "").strip()
        player_name = str(row.get("player") or "").strip()
        canonical_id = str(row.get("canonicalPlayerId") or row.get("canonical_player_id") or "").strip()

        if not source_id:
            if player_name:
                unresolved_names.add(player_name)
            continue

        if not canonical_id:
            canonical_id = f"{provider_key}:{source_id}"

        if source_id not in provider_map:
            provider_map[source_id] = {
                "canonical_player_id": canonical_id,
                "full_name": player_name,
                "aliases": [],
            }
            added += 1

    save_identity_map(payload)
    return {
        "provider": provider_key,
        "added": added,
        "providerMapSize": len(provider_map),
        "unresolvedCount": len(unresolved_names),
        "unresolvedSample": sorted(unresolved_names)[:100],
    }


def unresolved_identity_rows(
    *,
    source_provider: str,
    prop_rows: list[dict[str, Any]],
    limit: int = 100,
) -> list[dict[str, str]]:
    provider_key = source_provider.strip().lower()
    payload = load_identity_map()
    provider_map = payload.get("providers", {}).get(provider_key, {})
    unresolved: list[dict[str, str]] = []
    seen: set[str] = set()

    for row in prop_rows:
        source_id = str(row.get("sourcePlayerId") or row.get("source_player_id") or "").strip()
        player_name = str(row.get("player") or "").strip()
        if source_id and source_id in provider_map:
            continue
        key = f"{source_id}|{player_name}"
        if key in seen:
            continue
        seen.add(key)
        unresolved.append(
            {
                "source_player_id": source_id,
                "player": player_name,
            }
        )
        if len(unresolved) >= max(1, limit):
            break

    return unresolved


def resolve_player_identity(
    *,
    source_provider: str,
    source_player_id: str,
    player_name: str,
) -> dict[str, object]:
    payload = _load_identity_map()
    providers = payload.get("providers", {})
    provider_key = source_provider.strip().lower()
    provider_map = providers.get(provider_key, {})

    source_id = source_player_id.strip()
    if source_id:
        entry = provider_map.get(source_id)
        if isinstance(entry, dict):
            canonical = str(entry.get("canonical_player_id") or "").strip()
            if canonical:
                return {
                    "canonical_player_id": canonical,
                    "source_player_id": source_id,
                    "confidence": 1.0,
                    "matched_by": "provider_id_map",
                }
        return {
            "canonical_player_id": f"{provider_key}:{source_id}",
            "source_player_id": source_id,
            "confidence": 0.82,
            "matched_by": "provider_source_id",
        }

    # If the provider does not expose a stable player id, mark identity as unresolved
    # so it can be mapped explicitly through the identity-map API.
    unresolved_slug = _slug(player_name) or "unknown-player"
    return {
        "canonical_player_id": f"unresolved:{provider_key}:{unresolved_slug}",
        "source_player_id": "",
        "confidence": 0.0,
        "matched_by": "missing_source_player_id",
    }
