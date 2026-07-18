"""Explainable contextual, correlation, simulation, and alert engines."""

from math import asin, cos, radians, sin, sqrt
from random import Random
from statistics import fmean

from models.intelligence import (
    AlertCondition,
    CompoundAlertRequest,
    CorrelationRequest,
    FatigueRequest,
    GameScriptRequest,
    MatchupRequest,
    OfficiatingRequest,
    SimilarityRequest,
    ScheduleFatigueRequest, TravelLeg,
)
from services.historical_correlation_service import empirical_pair


def derive_schedule_fatigue(request: ScheduleFatigueRequest) -> dict[str, object]:
    games = sorted(request.previous_games, key=lambda game: game.starts_at)[-5:]
    if games:
        rest_hours = max(0.0, (request.upcoming_game.starts_at - games[-1].starts_at).total_seconds() / 3600)
        rest_days = max(0.0, rest_hours / 24 - 1)
    else:
        rest_days = 3.0
    route = games + [request.upcoming_game]
    legs = []
    for origin, destination in zip(route, route[1:]):
        lat1, lon1, lat2, lon2 = map(radians, (origin.latitude, origin.longitude,
                                                destination.latitude, destination.longitude))
        arc = 2 * asin(sqrt(sin((lat2 - lat1) / 2) ** 2 +
                              cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) ** 2))
        legs.append(TravelLeg(miles=3958.8 * arc,
                              timezone_change_hours=abs(destination.utc_offset_hours - origin.utc_offset_hours),
                              is_road_game=destination.is_road_game))
    recent = []
    for game in reversed(games):
        if not recent or (recent[-1].starts_at - game.starts_at).total_seconds() <= 48 * 3600:
            recent.append(game)
        else:
            break
    fatigue_request = FatigueRequest(rest_days=min(14, rest_days),
                                     recent_minutes=[game.minutes for game in games if game.minutes is not None],
                                     travel_legs=legs, consecutive_games=max(1, len(recent) + 1))
    result = fatigue_index(fatigue_request)
    result["derivedInputs"] = fatigue_request.model_dump()
    road_streak = 0
    for game in reversed(route):
        if not game.is_road_game:
            break
        road_streak += 1
    result["consecutiveRoadGames"] = road_streak
    return result


def fatigue_index(request: FatigueRequest) -> dict[str, object]:
    miles = sum(leg.miles for leg in request.travel_legs)
    zones = sum(leg.timezone_change_hours for leg in request.travel_legs)
    road_games = sum(1 for leg in request.travel_legs if leg.is_road_game)
    minutes = fmean(request.recent_minutes[-5:]) if request.recent_minutes else 30.0
    rest_load = max(0.0, 2.0 - request.rest_days) * 18
    score = min(100.0, rest_load + miles / 180 + zones * 4 + road_games * 3 +
                max(0, request.consecutive_games - 1) * 5 + max(0, minutes - 30) * .7)
    level = "HIGH" if score >= 65 else "ELEVATED" if score >= 40 else "NORMAL"
    return {
        "score": round(score, 1), "level": level, "travelMiles": round(miles),
        "timezoneHours": round(zones, 1), "averageRecentMinutes": round(minutes, 1),
        "projectionMultiplier": round(1 - score * .0018, 3),
        "explanation": f"{level.title()} load: {round(miles):,} miles, {request.rest_days:g} rest days, {road_games} road legs.",
    }


def officiating_adjustment(request: OfficiatingRequest) -> dict[str, object]:
    market = request.market.lower()
    if request.sport == "MLB" and ("strikeout" in market or market in {"k", "ks"}):
        multiplier = 1 + (request.strike_zone_width_index - 1) * .32
        driver = "home-plate strike-zone width"
    elif "free throw" in market or "foul" in market:
        multiplier = 1 + (request.crew_whistle_rate_index - 1) * .45
        driver = "crew whistle frequency"
    else:
        foul_risk = request.player_foul_rate * max(0, request.crew_whistle_rate_index - 1)
        multiplier = 1 - foul_risk * .2
        driver = "foul-trouble exposure"
    adjusted = request.baseline * multiplier
    return {"baseline": request.baseline, "adjustedProjection": round(adjusted, 2),
            "delta": round(adjusted - request.baseline, 2), "multiplier": round(multiplier, 3), "driver": driver}


def matchup_adjustment(request: MatchupRequest) -> dict[str, object]:
    market = request.market.lower()
    blitz = request.blitz_rate
    if "assist" in market:
        shift = blitz * .12 + request.switch_rate * -.03
    elif "point" in market:
        shift = blitz * -.14 + request.switch_rate * -.04
    else:
        shift = blitz * -.04 + request.switch_rate * -.02
    shift -= request.defender_difficulty * .1
    multiplier = max(.65, min(1.35, 1 + shift))
    return {"baseline": request.baseline, "adjustedProjection": round(request.baseline * multiplier, 2),
            "multiplier": round(multiplier, 3), "blitzRate": blitz, "switchRate": request.switch_rate,
            "explanation": "Blitz/switch tendencies shift creation from scoring toward passing." if blitz else "Defender and switching profile applied."}


def _market_family(market: str) -> str:
    text = market.lower()
    for key in ("passing", "receiving", "rushing", "assist", "point", "rebound", "three", "strikeout"):
        if key in text:
            return key
    return text


def _pair_correlation(first: object, second: object) -> tuple[float, str]:
    same_game = first.game_id and first.game_id == second.game_id
    a, b = _market_family(first.market), _market_family(second.market)
    score, reason = 0.0, "Different-game diversification"
    if same_game and {a, b} == {"passing", "receiving"}:
        score, reason = .62, "Passing and receiving production share the same completions"
    elif same_game and {a, b} == {"passing", "rushing"}:
        score, reason = -.28, "Pass-heavy and run-heavy scripts compete for volume"
    elif same_game and {a, b} == {"point", "assist"}:
        score, reason = .18, "High offensive output can lift both scoring and assists"
    elif first.player == second.player:
        score, reason = .35, "Multiple markets depend on the same player's minutes and role"
    if first.side != second.side:
        score *= -1
        reason += "; opposing sides invert the relationship"
    return score, reason


def correlation_matrix(request: CorrelationRequest) -> dict[str, object]:
    pairs = []
    scores = []
    for index, first in enumerate(request.legs):
        for second in request.legs[index + 1:]:
            empirical = empirical_pair(first, second)
            if empirical is not None:
                score = float(empirical["coefficient"])
                reason = f"Measured across {empirical['sampleSize']} overlapping historical games"
            else:
                score, reason = _pair_correlation(first, second)
            scores.append(score)
            pairs.append({"firstId": first.id, "secondId": second.id, "coefficient": round(score, 2),
                          "classification": "POSITIVE" if score >= .15 else "NEGATIVE" if score <= -.15 else "NEUTRAL",
                          "reason": reason, "source": empirical["source"] if empirical else "heuristic-fallback",
                          "sampleSize": empirical["sampleSize"] if empirical else 0,
                          "jointHitRate": empirical["jointHitRate"] if empirical else None})
    portfolio = fmean(abs(score) for score in scores) if scores else 0
    return {"pairs": pairs, "correlationRisk": round(portfolio, 2),
            "warning": "Concentrated outcome risk" if portfolio >= .35 else "Correlation is within a balanced range"}


def _cholesky(matrix: list[list[float]]) -> list[list[float]]:
    """Return a stable lower-triangular factor for a correlation matrix."""
    size = len(matrix)
    lower = [[0.0] * size for _ in range(size)]
    for row in range(size):
        for column in range(row + 1):
            subtotal = sum(lower[row][k] * lower[column][k] for k in range(column))
            if row == column:
                lower[row][column] = sqrt(max(1e-8, matrix[row][row] - subtotal))
            else:
                lower[row][column] = (matrix[row][column] - subtotal) / lower[column][column]
    return lower


def simulate_game_script(request: GameScriptRequest) -> dict[str, object]:
    impacts = []
    for prop in request.props:
        family = _market_family(prop.market)
        multiplier, reason = 1.0, "Baseline role retained"
        if "BLOWOUT" in request.script:
            multiplier, reason = (.84, "Starter volume typically falls in non-competitive minutes")
            if "bench" in prop.market.lower():
                multiplier, reason = (1.22, "Bench players absorb additional closing minutes")
        elif request.script == "SHOOTOUT":
            multiplier, reason = (1.15 if family in {"passing", "receiving", "point", "assist", "three"} else .96,
                                  "Fast, high-scoring script changes opportunity volume")
        elif request.script == "LOW_SCORING":
            multiplier, reason = (.87 if family in {"passing", "receiving", "point", "assist", "three"} else 1.06,
                                  "Low-scoring script suppresses offensive efficiency")
        hit_shift = (multiplier - 1) * (1 if prop.side == "OVER" else -1)
        baseline = prop.baseline_projection if prop.baseline_projection is not None else prop.line
        line = prop.line if prop.line is not None else baseline
        deviation = prop.volatility if prop.volatility is not None else max(1.0, (baseline or 10.0) * .22)
        impacts.append({"id": prop.id, "player": prop.player, "market": prop.market,
                        "projectionMultiplier": multiplier, "hitProbabilityShift": round(hit_shift, 3),
                        "adjustedProjection": round(baseline * multiplier, 2) if baseline is not None else None,
                        "line": line, "volatility": round(deviation, 3), "reason": reason})

    simulated = [index for index, prop in enumerate(request.props)
                 if impacts[index]["adjustedProjection"] is not None and impacts[index]["line"] is not None]
    if not simulated:
        return {"script": request.script, "impacts": impacts, "simulations": 0,
                "portfolioHitProbability": None, "method": "scenario-multiplier-only"}

    size = len(simulated)
    correlations = [[1.0 if row == column else 0.0 for column in range(size)] for row in range(size)]
    for row in range(size):
        for column in range(row):
            coefficient, _ = _pair_correlation(request.props[simulated[row]], request.props[simulated[column]])
            # Conservative clipping helps keep small heuristic matrices positive definite.
            correlations[row][column] = correlations[column][row] = max(-.45, min(.45, coefficient))
    factor = _cholesky(correlations)
    random = Random(request.seed)
    hits = [0] * size
    portfolio_hits = 0
    for _ in range(request.simulations):
        independent = [random.gauss(0, 1) for _ in range(size)]
        correlated = [sum(factor[row][column] * independent[column] for column in range(row + 1))
                      for row in range(size)]
        all_hit = True
        for position, impact_index in enumerate(simulated):
            prop, impact = request.props[impact_index], impacts[impact_index]
            outcome = float(impact["adjustedProjection"]) + correlated[position] * float(impact["volatility"])
            hit = outcome > float(impact["line"]) if prop.side == "OVER" else outcome < float(impact["line"])
            hits[position] += int(hit)
            all_hit = all_hit and hit
        portfolio_hits += int(all_hit)
    for position, impact_index in enumerate(simulated):
        impacts[impact_index]["hitProbability"] = round(hits[position] / request.simulations, 4)
    return {"script": request.script, "impacts": impacts, "simulations": request.simulations,
            "portfolioHitProbability": round(portfolio_hits / request.simulations, 4),
            "seed": request.seed, "method": "correlated-gaussian-monte-carlo"}


def similarity_matches(request: SimilarityRequest) -> dict[str, object]:
    target = request.recent_stretch
    matches = []
    for candidate in request.candidates:
        if len(candidate.stretch) != len(target):
            continue
        distance = sqrt(sum((a - b) ** 2 for a, b in zip(target, candidate.stretch)) / len(target))
        scale = max(1.0, abs(fmean(target)))
        matches.append({"player": candidate.player, "similarity": round(max(0, 1 - distance / scale), 4),
                        "nextGameValue": candidate.next_game_value, "context": candidate.context})
    matches.sort(key=lambda row: row["similarity"], reverse=True)
    selected = matches[:request.limit]
    similarity_weight = sum(float(row["similarity"]) for row in selected)
    next_projection = (
        sum(float(row["nextGameValue"]) * float(row["similarity"]) for row in selected)
        / similarity_weight
        if similarity_weight > 0
        else None
    )
    return {"player": request.player, "matches": selected,
            "analogNextGameProjection": round(next_projection, 2) if next_projection is not None else None,
            "engine": "pgvector-ready normalized sequence similarity"}


def sentiment_score(events: list[dict[str, str]]) -> dict[str, object]:
    weights = {"VIEW": 1, "SEARCH": 1.5, "CLICK": 2, "WATCHLIST": 4, "PICK_OVER": 5, "PICK_UNDER": -5}
    raw = sum(weights.get(event.get("action", ""), 0) for event in events)
    score = max(-100, min(100, raw))
    return {"score": round(score, 1), "label": "FOLLOW" if score >= 15 else "FADE" if score <= -15 else "NEUTRAL",
            "sampleSize": len(events), "overInterest": sum(e.get("action") == "PICK_OVER" for e in events),
            "underInterest": sum(e.get("action") == "PICK_UNDER" for e in events)}


def _compare(actual: object, condition: AlertCondition) -> bool:
    expected, op = condition.value, condition.operator
    try:
        if op == "EQ": return actual == expected
        if op == "NE": return actual != expected
        if op == "LT": return float(actual) < float(expected)
        if op == "LTE": return float(actual) <= float(expected)
        if op == "GT": return float(actual) > float(expected)
        if op == "GTE": return float(actual) >= float(expected)
        if op == "IN": return actual in expected  # type: ignore[operator]
        if op == "CONTAINS": return str(expected).lower() in str(actual).lower()
    except (TypeError, ValueError):
        return False
    return False


def evaluate_alert(request: CompoundAlertRequest) -> dict[str, object]:
    results = [{"field": c.field, "matched": _compare(request.snapshot.get(c.field), c),
                "actual": request.snapshot.get(c.field), "operator": c.operator, "expected": c.value}
               for c in request.conditions]
    triggered = all(r["matched"] for r in results) if request.logic == "ALL" else any(r["matched"] for r in results)
    return {"name": request.name, "triggered": triggered, "logic": request.logic, "conditions": results}
