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
    LEAN       a qualified model direction, but not a full-price play
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

from services.selectability_projection_service import break_even_for

# The decision codes are stable; the words on the card are not, and these
# are the words. A pass is the one that matters most: it is our opinion, and
# it reads as an invitation to decide rather than a door being closed --
# people who bet on a read are customers, not mistakes to correct.
PLAY_NOW = "PLAY_NOW"
SHOP = "SHOP"
WAIT = "WAIT"
LEAN = "LEAN"
PASS = "PASS"

# What a prop must clear beyond the break-even its own price implies.
#
# One global threshold was two mistakes at once. Measured on a live board,
# 641 props cleared 0.58 while only 245 of them beat the number their book was
# actually offering -- so 414 recommendations were negative expected value at
# the posted price, and separately, sportsbook props in the low fifties were
# being rejected while genuinely profitable.
#
# The bar is now the price plus a margin, because break-even differs by book:
# a pick'em leg needs about 57.8%, a -110 line needs 52.4%, and clearing
# either exactly is a coin flip that has already paid the vig.
PLAY_MARGIN_OVER_BREAK_EVEN = 0.02

# A lean is the model's qualified directional threshold. It can be a modest
# positive-value edge, or a strong direction whose current price is too
# expensive. The latter must say so plainly and can never become PLAY NOW.
LEAN_MARGIN_OVER_BREAK_EVEN = 0.005

# Retained for callers and tests that still reason in absolute terms. These
# are the pick'em equivalents of the margins above, not separate rules.
ACTIONABLE_PROBABILITY = 0.58

LEAN_PROBABILITY = 0.545

# Probability edge over the de-vigged market. Below this the model and the
# market disagree by less than the model's own error, which is not a signal.
MEANINGFUL_PROBABILITY_EDGE = 0.02

# Another book paying at least this much more is worth the trip.
SHOP_ODDS_GAIN = 0.06

# A line this much better elsewhere changes the bet, not just the price.
SHOP_LINE_GAIN = 0.5

# Expected value, after the price, below which a bet loses money however
# confident the model is. Measured on a live board, props the model liked at
# a median 68% still had a median expected value of -5.6%: the probability
# was real and the price had already taken it. Conviction without price is
# how a confident model loses money slowly.
MINIMUM_EXPECTED_VALUE_PERCENT = 1.0

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
    current_line = _float(getattr(prop, "line", None))
    # Half a point inside the projection keeps a little of the edge rather
    # than spending all of it, which is where these bets stop being worth it.
    if side == "OVER":
        threshold = round(projection - 0.5, 2)
        if threshold <= 0 or (
            current_line is not None and threshold < current_line
        ):
            return None
        return threshold
    threshold = round(projection + 0.5, 2)
    if current_line is not None and threshold > current_line:
        return None
    return threshold


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
    current_book = str(getattr(prop, "sportsbook", "") or "")
    if book.strip().casefold() == current_book.strip().casefold():
        return "", 0.0
    if best is None or current is None or not book:
        return "", 0.0
    gain = best - current
    return (book, round(gain, 4)) if gain >= SHOP_ODDS_GAIN else ("", 0.0)


def compute_verdict(prop: object) -> Verdict:
    """Decide what this prop is worth doing about."""

    released = str(getattr(prop, "recommendedSide", "") or "").strip().upper()
    if released not in {"OVER", "UNDER"}:
        released = ""
    verified_model = bool(
        getattr(prop, "recommendationAvailable", False)
    ) and bool(released)
    signal_source = "The model" if verified_model else "The available projection"

    # The release gate blanks recommendedSide on everything it will not put
    # its name to, which is most of the board. Reading only that field made
    # the verdict claim the model had no opinion on 1,574 props that each
    # carried a probability for both sides. The model's own numbers are the
    # honest source for what it thinks; the gate decides how loudly to say it.
    over = _float(getattr(prop, "modelOverProbability", None))
    under = _float(getattr(prop, "modelUnderProbability", None))
    side = released
    probability = _float(getattr(prop, "uncertaintyAdjustedProbability", None))
    if probability is None:
        probability = _float(getattr(prop, "fairProbability", None))
    if not side and over is not None and under is not None:
        side = "OVER" if over >= under else "UNDER"
        probability = max(over, under)
    # The price this prop must beat, taken from the odds the book posted
    # wherever it posts them rather than from an assumption about the book.
    break_even, break_even_source = break_even_for(prop)
    play_bar = break_even + PLAY_MARGIN_OVER_BREAK_EVEN
    lean_bar = break_even + LEAN_MARGIN_OVER_BREAK_EVEN
    edge = _float(getattr(prop, "probabilityEdge", None))
    confidence = int(_float(getattr(prop, "confidence", 0)) or 0)
    reasons: list[str] = []

    # --- PASS: nothing solid to judge, or nothing worth taking. -----------
    if not getattr(prop, "selectable", True):
        return Verdict(
            decision=PASS,
            side="",
            headline="TAKE A CHANCE — NOT BACKED",
            reason=(
                "We could not verify this one, so there is no read from us. "
                "Still yours to take if you like it."
            ),
            confidence=0,
            reasons=("unverified",),
        )
    if getattr(prop, "projection", None) is None:
        return Verdict(
            decision=PASS,
            side="",
            headline="TAKE A CHANCE — NOT BACKED",
            reason=(
                "We do not model this market yet, so we have no opinion to "
                "offer -- not a warning against it. Your read is the better "
                "one here."
            ),
            confidence=0,
            reasons=("no_projection",),
            recheck="When this market gains model coverage",
        )
    if not side or probability is None:
        return Verdict(
            decision=PASS,
            side="",
            headline="TAKE A CHANCE — NOT BACKED",
            reason=(
                "We do not see a lean either way on this one. That means it "
                "looks close to us, not that it is a bad bet -- your call."
            ),
            confidence=confidence,
            reasons=("no_side",),
        )
    if probability < lean_bar and probability >= LEAN_PROBABILITY:
        return Verdict(
            decision=LEAN,
            side=side,
            headline=f"LEAN {side}",
            reason=(
                f"{signal_source} leans {side.title()} at {probability * 100:.0f}%, "
                f"but this price needs {break_even * 100:.0f}% to break even. "
                "The direction qualifies as a lean; the posted price is not "
                "backed, so keep the stake smaller or find a better number."
            ),
            confidence=confidence,
            reasons=("directional_lean_price_not_cleared",),
            maximum_playable_line=_maximum_playable_line(prop, side),
        )
    if probability < lean_bar:
        return Verdict(
            decision=PASS,
            side=side,
            headline="TAKE A CHANCE — NOT BACKED",
            reason=(
                f"We have {side.title()} at {probability * 100:.0f}% and this "
                f"price needs {break_even * 100:.0f}% to break even, so we "
                "are not backing it. If you like the spot, it is your call."
            ),
            confidence=confidence,
            reasons=("probability_below_price",),
        )
    # The price decides, not the probability. A side the model likes at 74%
    # is a losing bet if the book has priced it at 80%, and most of what the
    # model likes is priced that way.
    # Expected value is a warning the prop carries, not a gate that removes
    # it. Making it a gate emptied every actionable section on the board,
    # and a prop that never appears cannot be judged by the person whose
    # money it is. The rule is to show it, say what is wrong with it, and
    # leave the choice where it belongs.
    expected_value = _float(getattr(prop, "evPercentage", None))
    priced_out = (
        expected_value is not None
        and expected_value < MINIMUM_EXPECTED_VALUE_PERCENT
    )
    if edge is not None and edge < MEANINGFUL_PROBABILITY_EDGE:
        return Verdict(
            decision=PASS,
            side=side,
            headline="TAKE A CHANCE — NOT BACKED",
            reason=(
                "We land about where the market does on this one, so there is "
                "no edge we can point to. Nothing wrong with the bet -- we "
                "just cannot claim an advantage. Your call."
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
            reason=f"{signal_source} favors {side.title()}, but the player is listed {injury}.",
            confidence=confidence,
            reasons=tuple(reasons),
            maximum_playable_line=maximum_line,
            recheck="After the injury report is final",
        )
    pregame = getattr(prop, "pregameAvailability", {})
    has_pregame_assessment = isinstance(pregame, dict) and bool(pregame)
    if has_pregame_assessment and str(pregame.get("status") or "") != "READY":
        reasons.append("pregame_availability_unsettled")
        warnings = list(pregame.get("warnings") or [])
        return Verdict(
            decision=WAIT,
            side=side,
            headline=f"WAIT ON {side}",
            reason=(
                str(warnings[0])
                if warnings
                else f"{signal_source} favors {side.title()}, but pregame availability is not settled."
            ),
            confidence=confidence,
            reasons=tuple(reasons),
            maximum_playable_line=maximum_line,
            recheck=str(pregame.get("recheck") or "After official pregame availability is confirmed"),
        )
    if not has_pregame_assessment and lineup in _UNSETTLED_LINEUPS:
        reasons.append("lineup_unconfirmed")
        return Verdict(
            decision=WAIT,
            side=side,
            headline=f"WAIT ON {side}",
            reason=f"{signal_source} favors {side.title()}, but the lineup is not confirmed.",
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

    if (
        str(getattr(prop, "sport", "") or "").strip().upper() == "WNBA"
        and not bool(getattr(prop, "wnbaResearchReady", False))
    ):
        reasons.append("wnba_minutes_or_role_uncertain")
        warnings = list(getattr(prop, "wnbaResearchWarnings", []) or [])
        return Verdict(
            decision=WAIT,
            side=side,
            headline=f"WAIT ON {side}",
            reason=(
                warnings[0]
                if warnings
                else "WNBA minutes or role evidence is not settled yet."
            ),
            confidence=confidence,
            reasons=tuple(reasons),
            maximum_playable_line=maximum_line,
            recheck="After minutes, role and lineup evidence are confirmed",
        )

    # --- SHOP: the edge is real, the price here is not the best. ----------
    book, gain = _better_price(prop, side)
    if book:
        return Verdict(
            decision=SHOP,
            side=side,
            headline=f"CHECK OTHER BOOKS — {side}",
            reason=f"{book} is paying materially better on the same side.",
            confidence=confidence,
            reasons=("better_price_elsewhere",),
            maximum_playable_line=maximum_line,
            better_price_at=book,
        )

    # --- PLAY NOW or LEAN: how much conviction the numbers support. -------
    # Not conditioned on the legacy gate having named the side. That gate
    # tests separation and expected value against the pre-calibration
    # probability; this has already tested the calibrated probability and the
    # price, which is the stricter pair. Deferring to it as well left 64 props
    # at a median 15% expected value labelled a lean while nine others with
    # the same credentials were called plays.
    if probability >= play_bar and not priced_out:
        return Verdict(
            decision=PLAY_NOW,
            side=side,
            headline=f"PLAY {side}",
            reason=(
                f"{signal_source} gives {side.title()} {probability * 100:.0f}% "
                f"against a price that needs {break_even * 100:.0f}%."
            ),
            confidence=confidence,
            reasons=(f"priced_from_{break_even_source}",),
            maximum_playable_line=maximum_line,
        )
    if probability >= play_bar and priced_out:
        # The model likes it and the price has already taken the edge. Said
        # plainly, and still offered: it is a judgement about value, not
        # about whether the bet is allowed.
        return Verdict(
            decision=LEAN,
            side=side,
            headline=f"LEAN {side}",
            reason=(
                f"{signal_source} gives {side.title()} {probability * 100:.0f}%, "
                f"but this price returns {expected_value:+.1f}% -- the number "
                "is largely in the line already. Your call."
            ),
            confidence=confidence,
            reasons=("priced_out",),
            maximum_playable_line=maximum_line,
        )
    lean_reason = (
        f"{signal_source} gives {side.title()} {probability * 100:.0f}%, but this "
        "has not cleared the release checks for a full play."
        if not released
        else f"A real but modest edge at {probability * 100:.0f}%. Smaller "
        "than a full play."
    )
    return Verdict(
        decision=LEAN,
        side=side,
        headline=f"LEAN {side}",
        reason=lean_reason,
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
