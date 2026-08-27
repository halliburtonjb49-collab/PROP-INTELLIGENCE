"""Best-effort OneSignal delivery for material watched-prop weakening."""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from urllib.request import Request, urlopen


_LAST_SENT: dict[str, datetime] = {}
_COOLDOWN = timedelta(hours=6)


def notify_material_weakening(*, user_id: str, legs: list[dict[str, object]]) -> int:
    app_id = os.getenv("ONESIGNAL_APP_ID", "").strip()
    api_key = os.getenv("ONESIGNAL_REST_API_KEY", "").strip()
    if not app_id or not api_key or not user_id.strip():
        return 0
    now = datetime.now(timezone.utc)
    delivered = 0
    for leg in legs:
        if leg.get("pi_change_status") != "WEAKENED" or leg.get("pi_material_change") is not True:
            continue
        key = f"{user_id}:{leg.get('prop_id')}:{leg.get('current_projection')}:{leg.get('current_confidence')}"
        if now - _LAST_SENT.get(key, datetime.min.replace(tzinfo=timezone.utc)) < _COOLDOWN:
            continue
        player = str(leg.get("player") or "Watched prop")
        payload = json.dumps({
            "app_id": app_id,
            "include_aliases": {"external_id": [user_id]},
            "target_channel": "push",
            "headings": {"en": "PI recommendation weakened"},
            "contents": {"en": f"{player} changed materially. Open Watch to review the new evidence."},
            "data": {"type": "pi_recalculation", "propId": leg.get("prop_id")},
        }).encode("utf-8")
        request = Request(
            "https://api.onesignal.com/notifications",
            data=payload,
            headers={"Authorization": f"Key {api_key}", "Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urlopen(request, timeout=8) as response:  # noqa: S310
                if 200 <= response.status < 300:
                    _LAST_SENT[key] = now
                    delivered += 1
        except Exception:
            continue
    return delivered
