from datetime import datetime, timezone, tzinfo
import os
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def app_timezone() -> tzinfo:
    configured = os.getenv("PROP_INTELLIGENCE_TIMEZONE", "America/Chicago").strip()
    try:
        return ZoneInfo(configured)
    except ZoneInfoNotFoundError:
        return datetime.now().astimezone().tzinfo or timezone.utc


def parse_to_utc_iso(value: object) -> str:
    if value is None:
        return ""

    text = str(value).strip()
    if not text:
        return ""

    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return ""

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)

    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def format_display_time(start_time_utc: object) -> str:
    start_time_iso = parse_to_utc_iso(start_time_utc)
    if not start_time_iso:
        return ""

    parsed = datetime.fromisoformat(start_time_iso.replace("Z", "+00:00"))
    local_time = parsed.astimezone(app_timezone())
    return local_time.strftime("%I:%M %p").lstrip("0")


def status_from_start_time(start_time_utc: object) -> str:
    start_time_iso = parse_to_utc_iso(start_time_utc)
    if not start_time_iso:
        return "UPCOMING"

    parsed = datetime.fromisoformat(start_time_iso.replace("Z", "+00:00"))
    now = datetime.now(timezone.utc)
    return "LIVE" if parsed <= now else "UPCOMING"
