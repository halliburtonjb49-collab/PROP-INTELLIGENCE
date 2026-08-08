"""How many props clear the bar, under the bar we have and one that prices.

The board carries roughly five thousand props and calls about seventy of
them plays. Whether a price-aware threshold fixes that or merely moves it is
not something to reason about from the outside: the answer depends on how
many props sit between a sportsbook's break-even and the single global
threshold, and nobody has counted them.

So this counts them. It changes no behaviour and decides nothing. It exists
so the question "how many props would actually be pickable" has an answer
drawn from the live board rather than an estimate.

The distinction it measures is this. A prop is only worth taking when the
model's probability beats what the price demands, and different books demand
different things. Pick'em sites paying even money on a two-leg slip need
about 57.8% per leg; a sportsbook at -110 needs 52.4%. One global threshold
of 0.58 is therefore two mistakes at once -- it waves through pick'em props
carrying no margin at all, and it rejects sportsbook props at 0.55 that are
genuinely profitable.
"""

from __future__ import annotations

from threading import Lock
from typing import Iterable

# Books that price a slip rather than a single bet. They post no odds per
# prop, so the break-even has to come from the payout structure instead.
PICKEM_BOOKS = frozenset(
    {"prizepicks", "underdog", "betr", "betr_us_dfs", "pick6", "sleeper"}
)

# What a pick'em leg has to clear. Two-leg power plays pay +137 equivalent,
# so a leg needs 57.8% before it returns anything.
PICKEM_BREAK_EVEN = 0.578

# What a standard -110 sportsbook line demands.
STANDARD_BREAK_EVEN = 0.524

# Clearing break-even exactly is not an edge, it is a coin flip that has
# already paid the vig. This is the margin required beyond it.
REQUIRED_MARGIN = 0.02

# The single global threshold in use today, kept here so the comparison is
# against what actually ships rather than a remembered number.
CURRENT_GLOBAL_THRESHOLD = 0.58

_lock = Lock()
_projection: dict[str, object] = {}

_KEY = "diagnostics:selectability-projection"
_TTL_SECONDS = 60 * 60 * 24


def _number(value: object) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def break_even_for(prop: object) -> tuple[float, str]:
    """What this prop's price demands, and where that figure came from.

    Real posted odds are preferred over any assumption. A book that tells us
    what it is paying should never be second-guessed by a constant.
    """

    probability = model_probability(prop)
    side_is_over = True
    over = _number(getattr(prop, "modelOverProbability", None))
    under = _number(getattr(prop, "modelUnderProbability", None))
    if over is not None and under is not None:
        side_is_over = over >= under
    elif probability is not None:
        projection = _number(getattr(prop, "projection", None))
        line = _number(getattr(prop, "line", None))
        if projection is not None and line is not None:
            side_is_over = projection >= line

    odds = _number(
        getattr(prop, "overDecimalOdds" if side_is_over else "underDecimalOdds", None)
    )
    if odds is not None and odds > 1:
        return 1 / odds, "offeredOdds"

    book = str(getattr(prop, "sportsbook", "") or "").strip().lower().replace(" ", "_")
    if book in PICKEM_BOOKS:
        return PICKEM_BREAK_EVEN, "pickemStructure"
    return STANDARD_BREAK_EVEN, "assumedStandard"


def model_probability(prop: object) -> float | None:
    """The probability the model stands behind for its preferred side."""

    for field in (
        "uncertaintyAdjustedProbability",
        "fairProbability",
    ):
        value = _number(getattr(prop, field, None))
        if value is not None:
            return value
    over = _number(getattr(prop, "modelOverProbability", None))
    under = _number(getattr(prop, "modelUnderProbability", None))
    if over is not None and under is not None:
        return max(over, under)
    return None


def _verdicts_by_sport(props: Iterable[object]) -> dict[str, object]:
    """Decisions per sport, and the gate behind each pass.

    Imported here so a diagnostic can never be the reason the verdict module
    fails to load.
    """

    from services.pi_verdict_service import compute_verdict

    out: dict[str, dict[str, int]] = {}
    for prop in props:
        sport = str(getattr(prop, "sport", "") or "UNKNOWN").upper()
        counts = out.setdefault(sport, {})
        try:
            verdict = compute_verdict(prop)
        except Exception:
            counts["error"] = counts.get("error", 0) + 1
            continue
        counts[verdict.decision] = counts.get(verdict.decision, 0) + 1
        if verdict.decision == "PASS" and verdict.reasons:
            gate = f"pass:{verdict.reasons[0]}"
            counts[gate] = counts.get(gate, 0) + 1
    return dict(sorted(out.items()))


def project(props: Iterable[object]) -> dict[str, object]:
    """Count what each rule would call pickable, and where they differ."""

    props_list = list(props)
    props = props_list
    total = 0
    modelled = 0
    current = 0
    priced = 0
    both = 0
    # Per sport, because a board-wide count cannot show a whole sport going
    # empty. WNBA is almost entirely pick'em, so a bar raised for pick'em
    # falls on one sport far harder than the total suggests.
    by_sport: dict[str, dict[str, int]] = {}
    gained: dict[str, int] = {}
    lost: dict[str, int] = {}
    by_source: dict[str, int] = {}

    for prop in props:
        total += 1
        probability = model_probability(prop)
        if probability is None:
            continue
        modelled += 1
        break_even, source = break_even_for(prop)
        by_source[source] = by_source.get(source, 0) + 1

        clears_current = probability >= CURRENT_GLOBAL_THRESHOLD
        clears_priced = probability >= break_even + REQUIRED_MARGIN
        current += 1 if clears_current else 0
        priced += 1 if clears_priced else 0
        if clears_current and clears_priced:
            both += 1
        sport = str(getattr(prop, "sport", "") or "UNKNOWN").upper()
        counts = by_sport.setdefault(
            sport, {"props": 0, "current": 0, "priced": 0}
        )
        counts["props"] += 1
        counts["current"] += 1 if clears_current else 0
        counts["priced"] += 1 if clears_priced else 0
        book = str(getattr(prop, "sportsbook", "") or "UNKNOWN").upper()
        if clears_priced and not clears_current:
            gained[book] = gained.get(book, 0) + 1
        elif clears_current and not clears_priced:
            lost[book] = lost.get(book, 0) + 1

    return {
        "props": total,
        "withModelProbability": modelled,
        "currentRule": {
            "threshold": CURRENT_GLOBAL_THRESHOLD,
            "pickable": current,
        },
        "priceAwareRule": {
            "pickemBreakEven": PICKEM_BREAK_EVEN,
            "standardBreakEven": STANDARD_BREAK_EVEN,
            "requiredMargin": REQUIRED_MARGIN,
            "pickable": priced,
        },
        "agreeOnBoth": both,
        # Where the two rules disagree, and on whose props. This is the whole
        # question: a price-aware bar is only worth having if what it adds is
        # real edge rather than merely more cards.
        "gainedByBook": dict(sorted(gained.items(), key=lambda kv: -kv[1])[:8]),
        "lostByBook": dict(sorted(lost.items(), key=lambda kv: -kv[1])[:8]),
        "breakEvenSource": by_source,
        # A sport with props and no playable ones is a section that renders
        # empty, which is worse than a smaller board -- it reads as broken.
        "bySport": dict(sorted(by_sport.items())),
        # What the verdict actually decided, and for a pass, which gate
        # stopped it. A count of playable props says a sport is empty; this
        # says why, and the five pass gates fail for very different reasons.
        "verdictsBySport": _verdicts_by_sport(props_list),
        "sportsWithNothingPlayable": sorted(
            sport
            for sport, counts in by_sport.items()
            if counts["props"] >= 25 and counts["priced"] == 0
        ),
    }


def record_projection(props: Iterable[object]) -> None:
    """Measure during a run that already holds the props, never on a request.

    Reading a distribution by walking every prop inside a request is what
    turned the operations endpoint into a 502 earlier; this is deliberately
    computed where the props are already in hand.
    """

    global _projection
    try:
        projection = project(props)
    except Exception:
        return
    with _lock:
        _projection = projection
    try:
        from services.distributed_cache_service import set_json

        set_json(_KEY, projection, ttl_seconds=_TTL_SECONDS)
    except Exception:
        # Diagnostics must never break a sync.
        pass


def selectability_projection() -> dict[str, object]:
    """The last projection, from whichever instance actually produced one."""

    with _lock:
        local = dict(_projection)
    if local:
        return local
    try:
        from services.distributed_cache_service import get_json

        shared = get_json(_KEY)
    except Exception:
        return {}
    return shared if isinstance(shared, dict) else {}
