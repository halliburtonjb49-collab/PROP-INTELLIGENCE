"""What today's board amounts to, said once, before anyone scrolls it.

Five thousand cards is not an answer to "what should I look at today". The
briefing is the answer: how many props the model would actually stand behind,
which ones lead, and -- the part most summaries leave out -- what today's
board cannot tell you.

That last section is the reason this exists in the form it does. A briefing
that reports only its plays reads as confidence, and confidence is the one
thing this board has repeatedly turned out not to have earned. A sport with
no props today, a market with no projection behind it, a slate that has not
refreshed: each of those changes what the plays are worth, and each of them
was invisible on a board that simply showed fewer cards.

So the caveats are not a footnote here. They are a section, they are counted,
and when there is nothing worth playing the briefing says so rather than
promoting the best of a bad slate.
"""

from __future__ import annotations

from datetime import date, datetime, timezone, tzinfo
from typing import Iterable, Sequence

# How many plays the briefing will name before it stops listing and starts
# summarising. A briefing that lists forty picks is a board with extra steps.
MAX_LEAD_PLAYS = 5

# Decisions worth surfacing at the top, strongest first.
_LEAD_DECISIONS = ("PLAY_NOW", "SHOP", "LEAN")


def _text(value: object) -> str:
    return str(value or "").strip()


def _number(value: object) -> float | None:
    try:
        return None if value is None else float(value)
    except (TypeError, ValueError):
        return None


def _verdict_of(prop: object) -> dict[str, object]:
    verdict = getattr(prop, "verdict", None)
    return verdict if isinstance(verdict, dict) else {}


def _timestamp(value: object) -> datetime | None:
    raw = _text(value)
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _trust_score(prop: object) -> int:
    return max(0, min(100, int(_number(getattr(prop, "piTrustScore", 0)) or 0)))


def _is_researchable(prop: object) -> bool:
    return bool(getattr(prop, "selectable", True)) and not bool(
        getattr(prop, "dataStale", False)
    )


def _lead_play(prop: object) -> dict[str, object]:
    verdict = _verdict_of(prop)
    return {
        "propId": _text(getattr(prop, "id", "")),
        "player": _text(getattr(prop, "player", "")),
        "sport": _text(getattr(prop, "sport", "")),
        "market": _text(getattr(prop, "market", "")),
        "line": _number(getattr(prop, "line", None)),
        "side": _text(verdict.get("side")),
        "decision": _text(verdict.get("decision")),
        "headline": _text(verdict.get("headline")),
        "reason": _text(verdict.get("reason")),
        "piTrustScore": _trust_score(prop),
        "piTrustBand": _text(getattr(prop, "piTrustBand", "")),
        "sportsbook": _text(getattr(prop, "sportsbook", "")),
        "expectedValuePercent": _number(getattr(prop, "evPercentage", None)),
    }


def _rank(prop: object) -> tuple[int, float]:
    verdict = _verdict_of(prop)
    decision = _text(verdict.get("decision"))
    order = {"PLAY_NOW": 3, "SHOP": 2, "LEAN": 1}.get(decision, 0)
    return (order, float(_trust_score(prop)))


def build_briefing(
    props: Iterable[object],
    *,
    empty_sports: Sequence[str] = (),
    generated_at: datetime | None = None,
    target_date: date | None = None,
    local_timezone: tzinfo = timezone.utc,
    now: datetime | None = None,
    stale_after_minutes: int | None = None,
) -> dict[str, object]:
    """Today's board reduced to what a person needs before deciding anything."""

    generated = generated_at or now or datetime.now(timezone.utc)
    if generated.tzinfo is None:
        generated = generated.replace(tzinfo=timezone.utc)
    current = now or generated
    if current.tzinfo is None:
        current = current.replace(tzinfo=timezone.utc)
    current = current.astimezone(timezone.utc)

    board: list[object] = []
    for prop in props:
        start = _timestamp(getattr(prop, "startTimeUtc", ""))
        if target_date is not None:
            if start is None or start.astimezone(local_timezone).date() != target_date:
                continue
            if start <= current:
                continue
        if stale_after_minutes is not None:
            updated = _timestamp(getattr(prop, "lastUpdatedUtc", ""))
            if updated is None or (
                current - updated
            ).total_seconds() > stale_after_minutes * 60:
                continue
        if bool(getattr(prop, "dataStale", False)):
            continue
        board.append(prop)
    counts: dict[str, int] = {}
    without_projection = 0
    unsettled = 0
    sports: set[str] = set()
    candidates: list[object] = []
    sport_rows: dict[str, dict[str, object]] = {}
    latest_update: datetime | None = None

    for prop in board:
        sport = _text(getattr(prop, "sport", ""))
        if sport:
            sport = sport.upper()
            sports.add(sport)
            sport_rows.setdefault(sport, {
                "sport": sport,
                "total": 0,
                "playable": 0,
                "playNow": 0,
                "shop": 0,
                "lean": 0,
                "wait": 0,
                "trustTotal": 0,
                "trustSamples": 0,
                "topPiTrust": 0,
            })
        updated = _timestamp(getattr(prop, "lastUpdatedUtc", ""))
        if updated is not None and (latest_update is None or updated > latest_update):
            latest_update = updated
        if getattr(prop, "projection", None) is None:
            without_projection += 1
        decision = _text(_verdict_of(prop).get("decision")) or "UNJUDGED"
        counts[decision] = counts.get(decision, 0) + 1
        searchable = _is_researchable(prop)
        if sport:
            row = sport_rows[sport]
            row["total"] = int(row["total"]) + 1
            if searchable:
                trust = _trust_score(prop)
                row["trustTotal"] = int(row["trustTotal"]) + trust
                row["trustSamples"] = int(row["trustSamples"]) + 1
                row["topPiTrust"] = max(int(row["topPiTrust"]), trust)
            if searchable and decision in _LEAD_DECISIONS:
                row["playable"] = int(row["playable"]) + 1
                key = {"PLAY_NOW": "playNow", "SHOP": "shop", "LEAN": "lean"}[decision]
                row[key] = int(row[key]) + 1
            elif searchable and decision == "WAIT":
                row["wait"] = int(row["wait"]) + 1
        if searchable and decision == "WAIT":
            unsettled += 1
        if searchable and decision in _LEAD_DECISIONS:
            candidates.append(prop)

    candidates.sort(key=_rank, reverse=True)
    leads = [_lead_play(prop) for prop in candidates[:MAX_LEAD_PLAYS]]

    sports_to_research: list[dict[str, object]] = []
    for row in sport_rows.values():
        samples = int(row.pop("trustSamples"))
        trust_total = int(row.pop("trustTotal"))
        row["averagePiTrust"] = round(trust_total / samples) if samples else 0
        if int(row["playable"]) > 0:
            sports_to_research.append(row)
    sports_to_research.sort(
        key=lambda row: (
            int(row["playable"]),
            int(row["playNow"]),
            int(row["shop"]),
            int(row["averagePiTrust"]),
        ),
        reverse=True,
    )

    actionable = sum(int(row["playable"]) for row in sport_rows.values())
    caveats: list[str] = []
    if without_projection:
        caveats.append(
            f"{without_projection} props carry no model projection and are "
            "shown for research only."
        )
    if unsettled:
        caveats.append(
            f"{unsettled} props have a real edge but something unresolved -- "
            "a lineup or an injury -- and are worth rechecking."
        )
    for sport in sorted(empty_sports):
        caveats.append(f"No {sport} props are available on today's board.")

    return {
        "generatedAt": generated.isoformat(),
        "sourceUpdatedAt": latest_update.isoformat() if latest_update else None,
        "boardDate": target_date.isoformat() if target_date else None,
        "propsOnBoard": len(board),
        "sportsCovered": sorted(sports),
        "verdictCounts": counts,
        "actionable": actionable,
        "leadPlays": leads,
        "sportsToResearch": sports_to_research,
        # Said plainly rather than implied by a short list. A quiet day is a
        # finding, and dressing one up as a slate is how a reader ends up
        # betting the best of nothing.
        "quietDay": actionable == 0,
        "summary": (
            "Nothing on today's board clears the bar. That is a result, not a "
            "gap -- the model would rather say so than promote the best of a "
            "thin slate."
            if actionable == 0
            else f"{actionable} of {len(board)} props clear the bar today."
        ),
        "caveats": caveats,
    }
