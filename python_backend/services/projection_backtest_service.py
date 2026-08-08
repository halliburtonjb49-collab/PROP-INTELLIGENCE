"""Grade the projection against outcomes it has already seen, market by market.

The board's record is 409 graded picks, 408 of them in the tier nobody should
bet, so it cannot say whether the model works. Waiting for a real sample means
waiting weeks, and every defect found today -- a fantasy score projected from
raw points, a rush+reception line projected from rushing alone, a
hits+runs+rbis line projected from hits -- was live for all of that time
without a single number reporting it.

None of that needed new data. The game logs are already stored; what was
missing was anyone replaying them. This walks each player's history forward:
project game N from games 1..N-1 only, compare to what actually happened,
never letting the model see the game it is being asked about.

The measure that matters most is bias, not error. A market projected from the
wrong statistic does not look noisy, it looks confidently wrong in one
direction -- and every defect found today would have shown here as a bias of
half the line or more, on the first run, without anyone knowing what to look
for.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Iterable, Sequence

# Below this a player's history cannot be walked forward meaningfully: the
# first projections would be built from almost nothing and would report the
# cold start rather than the model.
MINIMUM_HISTORY = 6

# Games held out per player at most, newest first. Older games are the ones
# the projection was always weakest on and they are not what the board runs
# against today.
MAXIMUM_HELD_OUT = 20


@dataclass(frozen=True)
class MarketGrade:
    """How the projection did on one market, on games it did not see."""

    sport: str
    market: str
    sample_size: int
    mean_absolute_error: float
    bias: float
    baseline_mean_absolute_error: float
    beat_baseline_rate: float

    @property
    def improves_on_baseline(self) -> bool:
        return self.mean_absolute_error < self.baseline_mean_absolute_error

    @property
    def bias_ratio(self) -> float:
        """Bias as a share of the typical error.

        A market projected from the wrong statistic shows a bias large
        relative to its own error. Noise averages out; a wrong quantity does
        not.
        """

        if self.mean_absolute_error <= 0:
            return 0.0
        return self.bias / self.mean_absolute_error

    @property
    def suspect(self) -> bool:
        """Whether this market looks like it is measuring something else."""

        return abs(self.bias_ratio) >= 0.5

    def as_payload(self) -> dict[str, object]:
        return {
            "sport": self.sport,
            "market": self.market,
            "sampleSize": self.sample_size,
            "meanAbsoluteError": round(self.mean_absolute_error, 4),
            "bias": round(self.bias, 4),
            "baselineMeanAbsoluteError": round(
                self.baseline_mean_absolute_error, 4
            ),
            "beatBaselineRate": round(self.beat_baseline_rate, 4),
            "biasRatio": round(self.bias_ratio, 4),
            "improvesOnBaseline": self.improves_on_baseline,
            "suspect": self.suspect,
        }


def walk_forward(
    history: Sequence[float],
    *,
    project: Callable[[Sequence[float]], float | None],
    minimum_history: int = MINIMUM_HISTORY,
    maximum_held_out: int = MAXIMUM_HELD_OUT,
) -> list[tuple[float, float, float]]:
    """Replay one player's history, oldest first, holding each game out.

    Returns (projected, actual, baseline) per held-out game. The baseline is
    the plain mean of everything before it, which is the thing any weighting
    scheme has to beat to have earned its complexity.
    """

    if len(history) <= minimum_history:
        return []
    results: list[tuple[float, float, float]] = []
    start = max(minimum_history, len(history) - maximum_held_out)
    for index in range(start, len(history)):
        past = history[:index]
        projected = project(past)
        if projected is None:
            continue
        baseline = sum(past) / len(past)
        results.append((float(projected), float(history[index]), baseline))
    return results


def grade_market(
    sport: str,
    market: str,
    histories: Iterable[Sequence[float]],
    *,
    project: Callable[[Sequence[float]], float | None],
) -> MarketGrade | None:
    """Grade one market across every player who has enough history."""

    errors: list[float] = []
    signed: list[float] = []
    baseline_errors: list[float] = []
    beat = 0

    for history in histories:
        for projected, actual, baseline in walk_forward(history, project=project):
            error = abs(projected - actual)
            baseline_error = abs(baseline - actual)
            errors.append(error)
            # Signed, and in the direction the card would be wrong: a
            # projection below the outcome argues Under when Over landed.
            signed.append(projected - actual)
            baseline_errors.append(baseline_error)
            if error < baseline_error:
                beat += 1

    if not errors:
        return None
    return MarketGrade(
        sport=sport,
        market=market,
        sample_size=len(errors),
        mean_absolute_error=sum(errors) / len(errors),
        bias=sum(signed) / len(signed),
        baseline_mean_absolute_error=sum(baseline_errors) / len(baseline_errors),
        beat_baseline_rate=beat / len(errors),
    )


def summarize(grades: Sequence[MarketGrade]) -> dict[str, object]:
    """The report a person reads before trusting any of this.

    Suspect markets lead. A market whose bias is large next to its own error
    is not a weak model, it is a model answering a different question, and
    that is the failure this exists to surface.
    """

    ranked = sorted(grades, key=lambda grade: -abs(grade.bias_ratio))
    suspect = [grade for grade in ranked if grade.suspect]
    graded = len(grades)
    improving = sum(1 for grade in grades if grade.improves_on_baseline)
    return {
        "marketsGraded": graded,
        "totalSampleSize": sum(grade.sample_size for grade in grades),
        "marketsImprovingOnBaseline": improving,
        "marketsSuspect": len(suspect),
        # Named rather than counted, because the whole value is knowing which.
        "suspectMarkets": [grade.as_payload() for grade in suspect],
        "markets": [grade.as_payload() for grade in ranked],
        "verdict": (
            "no market looks like it is measuring the wrong statistic"
            if not suspect
            else f"{len(suspect)} market(s) show a bias large enough to suggest "
            "the projection is answering a different question"
        ),
    }


def grade_basketball_markets(sport: str = "WNBA") -> dict[str, object]:
    """Grade every basketball market against the logs already stored.

    Uses the same value resolver the projection itself uses, so a market
    reading the wrong column here is reading it in production too.
    """

    from services.baseline_projection_service import (
        _INDEX,
        basketball_market_value,
        compute_baseline_projection,
    )
    from services.market_config import SPORT_MARKETS

    _INDEX.ensure_loaded()
    key = "basketball_wnba" if sport == "WNBA" else "basketball_nba"
    grades: list[MarketGrade] = []

    for market in sorted(SPORT_MARKETS.get(key, ())):
        histories: list[list[float]] = []
        for (row_sport, _player), rows in _INDEX.basketball.items():
            if row_sport != sport:
                continue
            values = [
                value
                for row in rows
                if (value := basketball_market_value(market, row)) is not None
            ]
            if len(values) > MINIMUM_HISTORY:
                histories.append(values)
        if not histories:
            continue

        def project(past: Sequence[float]) -> float | None:
            result = compute_baseline_projection(
                list(past), line=0.0, sport=sport, market=market,
            )
            return None if result is None else float(result.projection)

        grade = grade_market(sport, market, histories, project=project)
        if grade is not None:
            grades.append(grade)

    return summarize(grades)


_GRADE_KEY = "diagnostics:projection-grade"
_GRADE_TTL_SECONDS = 60 * 60 * 24 * 2


def record_projection_grade(sports: Sequence[str] = ("WNBA", "NBA")) -> None:
    """Grade during a run that can afford it, never on a request.

    Replaying every player's history is far too slow to answer a web request
    with -- putting a whole-board walk on the operations endpoint is what
    turned it into a 502 earlier today -- so this runs inside the sync and
    publishes what it found.
    """

    reports: dict[str, object] = {}
    for sport in sports:
        try:
            report = grade_basketball_markets(sport)
        except Exception:
            continue
        if report.get("marketsGraded"):
            reports[sport] = report
    if not reports:
        return
    try:
        from services.distributed_cache_service import set_json

        set_json(_GRADE_KEY, reports, ttl_seconds=_GRADE_TTL_SECONDS)
    except Exception:
        # Diagnostics must never break a sync.
        pass


def projection_grade_snapshot() -> dict[str, object]:
    """The last grade, from whichever instance produced one."""

    try:
        from services.distributed_cache_service import get_json

        value = get_json(_GRADE_KEY)
    except Exception:
        return {}
    return value if isinstance(value, dict) else {}
