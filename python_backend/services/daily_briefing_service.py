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

from datetime import datetime, timezone
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
        "confidence": int(_number(verdict.get("confidence")) or 0),
        "sportsbook": _text(getattr(prop, "sportsbook", "")),
        "expectedValuePercent": _number(getattr(prop, "evPercentage", None)),
    }


def _rank(prop: object) -> tuple[int, float]:
    verdict = _verdict_of(prop)
    decision = _text(verdict.get("decision"))
    order = {"PLAY_NOW": 3, "SHOP": 2, "LEAN": 1}.get(decision, 0)
    return (order, _number(verdict.get("confidence")) or 0.0)


def build_briefing(
    props: Iterable[object],
    *,
    empty_sports: Sequence[str] = (),
    generated_at: datetime | None = None,
) -> dict[str, object]:
    """Today's board reduced to what a person needs before deciding anything."""

    board = list(props)
    counts: dict[str, int] = {}
    without_projection = 0
    unsettled = 0
    sports: set[str] = set()
    candidates: list[object] = []

    for prop in board:
        sport = _text(getattr(prop, "sport", ""))
        if sport:
            sports.add(sport.upper())
        if getattr(prop, "projection", None) is None:
            without_projection += 1
        decision = _text(_verdict_of(prop).get("decision")) or "UNJUDGED"
        counts[decision] = counts.get(decision, 0) + 1
        if decision == "WAIT":
            unsettled += 1
        if decision in _LEAD_DECISIONS:
            candidates.append(prop)

    candidates.sort(key=_rank, reverse=True)
    leads = [_lead_play(prop) for prop in candidates[:MAX_LEAD_PLAYS]]

    actionable = sum(counts.get(decision, 0) for decision in _LEAD_DECISIONS)
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
        "generatedAt": (generated_at or datetime.now(timezone.utc)).isoformat(),
        "propsOnBoard": len(board),
        "sportsCovered": sorted(sports),
        "verdictCounts": counts,
        "actionable": actionable,
        "leadPlays": leads,
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
