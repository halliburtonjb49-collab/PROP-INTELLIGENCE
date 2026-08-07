"""One conclusion per prop, in place of six signals that must be assembled.

A card already carries a system lean, a model confidence, a suggested pick, a
set of evidence tags, a pick grade and an explanation. Each is true. Together
they ask the reader to do the reasoning: weigh six partial answers and decide
what the app actually thinks. Most people will not, and the ones who do will
sometimes reach a conclusion the model would not endorse.

The verdict is that reasoning, done once and stated plainly:

    PLAY NOW   the edge is real, the inputs are settled, act on it
    SHOP       the edge is real but this price is not the best available
    WAIT       the edge is real but something material is still unknown
    LEAN       a genuine but small edge, playable at a smaller size
    PASS       no edge worth taking, or nothing solid to judge it on

The order matters more than any single threshold. PASS is decided first,
because a prop with nothing behind it should never be dressed up by a later
rule; then WAIT, because acting on unsettled information is the expensive
mistake; then SHOP, because a real edge at a beatable price is still worth
taking, just not here.

Nothing here computes a new probability. Every input already exists on the
prop; this decides what they add up to.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Sequence

PLAY_NOW = "PLAY_NOW"
SHOP = "SHOP"
WAIT = "WAIT"
LEAN = "LEAN"
PASS = "PASS"

# Probability the release gate already requires before a pick is shown at all.
# Reused rather than reinvented so the verdict cannot disagree with the board.
ACTIONABLE_PROBABILITY = 0.58

# A lean is a real but modest edge: enough to note, not enough to press.
LEAN_PROBABILITY = 0.545

# Probability edge over the de-vigged market. Below this the model and the
# market disagree by less than the model's own error, which is not a signal.
MEANINGFUL_PROBABILITY_EDGE = 0.02

# Another book paying at least this much more is worth the trip.
SHOP_ODDS_GAIN = 0.06

# A line this much better elsewhere changes the bet, not just the price.
SHOP_LINE_GAIN = 0.5

_UNSETTLED_LINEUPS = frozenset({"", "unknown", "unconfirmed", "projected", "expected"})
_DOUBTFUL_INJURIES = frozenset({"questionable", "doubtful", "day-to-day", "probable"})


@dataclass(frozen=True)
class Verdict:
    """What the app thinks, and why."""

    decision: str
    side: str
    headline: str
    reason: str
    confidence: int
    reasons: tuple[str, ...] = field(default=())
    # The number past which the edge is gone, so a shopper knows when to stop.
    maximum_playable_line: float | None = None
    better_price_at: str = ""
    recheck: str = ""

    @property
    def is_actionable(self) -> bool:
        return self.decision in {PLAY_NOW, SHOP, LEAN}


def _float(value: object) -> float | None:
    try:
        return None if value is None else float(value)
    except (TypeError, ValueError):
        return None


def _maximum_playable_line(prop: object, side: str) -> float | None:
    """The line at which the projection stops beating the market.

    A projection of 7.2 against a line of 5.5 is not an argument for taking
    6.5 as well, and shoppers need to know where the edge ends rather than
    guessing from the edge's size.
    """

    projection = _float(getattr(prop, "projection", None))
    if projection is None:
        return None
    # Half a point inside the projection keeps a little of the edge rather
    # than spending all of it, which is where these bets stop being worth it.
    if side == "OVER":
        return round(projection - 0.5, 2)
    return round(projection + 0.5, 2)


def _better_price(prop: object, side: str) -> tuple[str, float]:
    """A book paying materially more for the same side, if there is one."""

    if side == "OVER":
        best = _float(getattr(prop, "bestOverOdds", None))
        current = _float(getattr(prop, "overDecimalOdds", None))
        book = str(getattr(prop, "bestOverBook", "") or "")
    else:
        best = _float(getattr(prop, "bestUnderOdds", None))
        current = _float(getattr(prop, "underDecimalOdds", None))
        book = str(getattr(prop, "bestUnderBook", "") or "")
    if best is None or current is None or not book:
        return "", 0.0
    gain = best - current
    return (book, round(gain, 4)) if gain >= SHOP_ODDS_GAIN else ("", 0.0)


def compute_verdict(prop: object) -> Verdict:
    """Decide what this prop is worth doing about."""

    side = str(getattr(prop, "recommendedSide", "") or "").strip().upper()
    if side not in {"OVER", "UNDER"}:
        side = ""
    probability = _float(getattr(prop, "uncertaintyAdjustedProbability", None))
    if probability is None:
        probability = _float(getattr(prop, "fairProbability", None))
    edge = _float(getattr(prop, "probabilityEdge", None))
    confidence = int(_float(getattr(prop, "confidence", 0)) or 0)
    reasons: list[str] = []

    # --- PASS: nothing solid to judge, or nothing worth taking. -----------
    if not getattr(prop, "selectable", True):
        return Verdict(
            decision=PASS,
            side="",
            headline="PASS",
            reason="This prop could not be verified.",
            confidence=0,
            reasons=("unverified",),
        )
    if getattr(prop, "projection", None) is None:
        return Verdict(
            decision=PASS,
            side="",
            headline="PASS",
            reason="No model projection for this market yet.",
            confidence=0,
            reasons=("no_projection",),
            recheck="When this market gains model coverage",
        )
    if not side or probability is None:
        return Verdict(
            decision=PASS,
            side="",
            headline="PASS",
            reason="The model does not favour either side here.",
            confidence=confidence,
            reasons=("no_side",),
        )
    if probability < LEAN_PROBABILITY:
        return Verdict(
            decision=PASS,
            side=side,
            headline="PASS",
            reason=(
                f"The model gives {side.title()} {probability * 100:.0f}%, "
                "which is not worth the vig."
            ),
            confidence=confidence,
            reasons=("probability_below_threshold",),
        )
    if edge is not None and edge < MEANINGFUL_PROBABILITY_EDGE:
        return Verdict(
            decision=PASS,
            side=side,
            headline="PASS",
            reason=(
                "The model and the market agree here, so there is nothing to "
                "take."
            ),
            confidence=confidence,
            reasons=("no_edge_over_market",),
        )

    maximum_line = _maximum_playable_line(prop, side)

    # --- WAIT: the edge is real but something material is still unknown. ---
    lineup = str(getattr(prop, "lineupStatus", "") or "").strip().lower()
    injury = str(getattr(prop, "injuryStatus", "") or "").strip().lower()
    if injury in _DOUBTFUL_INJURIES:
        reasons.append("injury_unresolved")
        return Verdict(
            decision=WAIT,
            side=side,
            headline=f"WAIT ON {side}",
            reason=f"The edge is real, but the player is listed {injury}.",
            confidence=confidence,
            reasons=tuple(reasons),
            maximum_playable_line=maximum_line,
            recheck="After the injury report is final",
        )
    if lineup in _UNSETTLED_LINEUPS:
        reasons.append("lineup_unconfirmed")
        return Verdict(
            decision=WAIT,
            side=side,
            headline=f"WAIT ON {side}",
            reason="The edge is real, but the lineup is not confirmed.",
            confidence=confidence,
            reasons=tuple(reasons),
            maximum_playable_line=maximum_line,
            recheck="After lineup confirmation",
        )
    if getattr(prop, "dataStale", False):
        reasons.append("stale_odds")
        return Verdict(
            decision=WAIT,
            side=side,
            headline=f"WAIT ON {side}",
            reason="This price has not refreshed recently enough to trust.",
            confidence=confidence,
            reasons=tuple(reasons),
            maximum_playable_line=maximum_line,
            recheck="After the next odds refresh",
        )

    # --- SHOP: the edge is real, the price here is not the best. ----------
    book, gain = _better_price(prop, side)
    if book:
        return Verdict(
            decision=SHOP,
            side=side,
            headline=f"SHOP {side}",
            reason=f"{book} is paying materially better on the same side.",
            confidence=confidence,
            reasons=("better_price_elsewhere",),
            maximum_playable_line=maximum_line,
            better_price_at=book,
        )

    # --- PLAY NOW or LEAN: how much conviction the numbers support. -------
    if probability >= ACTIONABLE_PROBABILITY:
        return Verdict(
            decision=PLAY_NOW,
            side=side,
            headline=f"PLAY {side} NOW",
            reason=(
                f"The model gives {side.title()} {probability * 100:.0f}% "
                "against a settled line."
            ),
            confidence=confidence,
            maximum_playable_line=maximum_line,
        )
    return Verdict(
        decision=LEAN,
        side=side,
        headline=f"LEAN {side}",
        reason=(
            f"A real but modest edge at {probability * 100:.0f}%. Smaller "
            "than a full play."
        ),
        confidence=confidence,
        maximum_playable_line=maximum_line,
    )


def verdict_payload(verdict: Verdict) -> dict[str, object]:
    """The verdict as the card reads it."""

    return {
        "decision": verdict.decision,
        "side": verdict.side,
        "headline": verdict.headline,
        "reason": verdict.reason,
        "confidence": verdict.confidence,
        "reasons": list(verdict.reasons),
        "maximumPlayableLine": verdict.maximum_playable_line,
        "betterPriceAt": verdict.better_price_at,
        "recheck": verdict.recheck,
        "actionable": verdict.is_actionable,
    }


def summarize(verdicts: Sequence[Verdict]) -> dict[str, int]:
    """How many of each decision, for a briefing or a board header."""

    counts = {PLAY_NOW: 0, SHOP: 0, WAIT: 0, LEAN: 0, PASS: 0}
    for verdict in verdicts:
        counts[verdict.decision] = counts.get(verdict.decision, 0) + 1
    return counts
