from collections.abc import Iterable
from typing import Any

from config.prop_sites import (
    normalize_prop_site,
)
from models.prop_builder import (
    PropBuilderLeg,
    PropBuilderRequest,
    PropBuilderResponse,
    PropReplacementRequest,
)
from services.market_normalizer import (
    normalize_market,
)
from services.prop_builder_explanation_service import (
    get_market_performance_lookup,
)
from services.prop_builder_strategy_service import (
    get_prop_builder_strategy,
)

SPORT_ALIASES = {
    "basketball_wnba": "wnba",
    "wnba": "wnba",
    "basketball_nba": "nba",
    "nba": "nba",
    "baseball_mlb": "mlb",
    "mlb": "mlb",
    "americanfootball_nfl": "nfl",
    "football_nfl": "nfl",
    "nfl": "nfl",
    "icehockey_nhl": "nhl",
    "hockey_nhl": "nhl",
    "nhl": "nhl",
}

RISK_MODE_SETTINGS = {
    "SAFE": {
        "minimum_edge": 70,
        "minimum_confidence": 75,
        "maximum_legs": 3,
        "same_game_allowed": False,
        "minimum_sports": 1,
    },
    "BALANCED": {
        "minimum_edge": 60,
        "minimum_confidence": 65,
        "maximum_legs": 5,
        "same_game_allowed": False,
        "minimum_sports": 1,
    },
    "AGGRESSIVE": {
        "minimum_edge": 50,
        "minimum_confidence": 55,
        "maximum_legs": 8,
        "same_game_allowed": True,
        "minimum_sports": 1,
    },
}


def _risk_settings(
    risk_mode: str,
) -> dict[str, int | bool]:
    return RISK_MODE_SETTINGS.get(
        risk_mode.upper(),
        RISK_MODE_SETTINGS["BALANCED"],
    )


def _safe_int(
    value: Any,
    default: int = 0,
) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _safe_int_or_none(
    value: object,
) -> int | None:
    if value is None:
        return None
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def _safe_float(
    value: Any,
) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _safe_text(
    value: Any,
) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _row_value(
    row: Any,
    key: str,
    default: Any = None,
) -> Any:
    try:
        value = row[key]
    except (KeyError, IndexError, TypeError):
        return default
    return default if value is None else value


def _choose_side(
    row: Any,
    preference: str,
) -> tuple[str, float | None]:
    recommended_pick = str(
        _row_value(row, "pick", "OVER")
    ).upper()
    over_odds = _safe_float(
        _row_value(row, "over_odds")
    )
    under_odds = _safe_float(
        _row_value(row, "under_odds")
    )

    if preference == "OVER":
        return "OVER", over_odds
    if preference == "UNDER":
        return "UNDER", under_odds
    if recommended_pick == "UNDER":
        return "UNDER", under_odds
    return "OVER", over_odds


def _normalized_values(
    values: Iterable[str],
) -> set[str]:
    return {
        value.strip().lower()
        for value in values
        if value.strip()
    }


def _normalize_sport(value: str) -> str:
    normalized = value.strip().lower()
    return SPORT_ALIASES.get(
        normalized,
        normalized,
    )


def _candidate_score(
    leg: PropBuilderLeg,
) -> tuple[int, int]:
    return (
        leg.confidence,
        leg.edge,
    )


def _normalized_key(value: str) -> str:
    return " ".join(
        value.strip().lower().split()
    )


def _candidate_team_keys(
    candidate: PropBuilderLeg,
) -> set[str]:
    teams = {
        _normalized_key(
            candidate.player_team
        ),
        _normalized_key(
            candidate.home_team
        ),
        _normalized_key(
            candidate.away_team
        ),
    }
    return {
        team
        for team in teams
        if team
    }


def _can_add_candidate(
    *,
    candidate: PropBuilderLeg,
    player_counts: dict[str, int],
    event_counts: dict[str, int],
    team_counts: dict[str, int],
    correlation_guard_enabled: bool,
    maximum_legs_per_player: int,
    maximum_legs_per_game: int,
    maximum_legs_per_team: int,
) -> bool:
    if not correlation_guard_enabled:
        return True

    player_key = _normalized_key(
        candidate.player
    )
    if (
        player_key
        and player_counts.get(
            player_key,
            0,
        ) >= maximum_legs_per_player
    ):
        return False

    if (
        candidate.event_id
        and event_counts.get(
            candidate.event_id,
            0,
        ) >= maximum_legs_per_game
    ):
        return False

    for team_key in _candidate_team_keys(
        candidate
    ):
        if (
            team_counts.get(team_key, 0)
            >= maximum_legs_per_team
        ):
            return False

    return True


def _record_candidate(
    *,
    candidate: PropBuilderLeg,
    player_counts: dict[str, int],
    event_counts: dict[str, int],
    team_counts: dict[str, int],
) -> None:
    player_key = _normalized_key(
        candidate.player
    )
    if player_key:
        player_counts[player_key] = (
            player_counts.get(
                player_key,
                0,
            )
            + 1
        )

    if candidate.event_id:
        event_counts[candidate.event_id] = (
            event_counts.get(
                candidate.event_id,
                0,
            )
            + 1
        )

    for team_key in _candidate_team_keys(
        candidate
    ):
        team_counts[team_key] = (
            team_counts.get(
                team_key,
                0,
            )
            + 1
        )


def _correlation_warnings(
    legs: list[PropBuilderLeg],
) -> list[str]:
    warnings: list[str] = []
    event_counts: dict[str, int] = {}
    player_counts: dict[str, int] = {}
    team_counts: dict[str, int] = {}

    for leg in legs:
        player_key = _normalized_key(
            leg.player
        )
        if player_key:
            player_counts[player_key] = (
                player_counts.get(
                    player_key,
                    0,
                )
                + 1
            )

        if leg.event_id:
            event_counts[leg.event_id] = (
                event_counts.get(
                    leg.event_id,
                    0,
                )
                + 1
            )

        for team in _candidate_team_keys(leg):
            team_counts[team] = (
                team_counts.get(team, 0)
                + 1
            )

    if any(
        count > 1
        for count in player_counts.values()
    ):
        warnings.append(
            "The slip contains multiple props "
            "for the same player."
        )

    if any(
        count > 1
        for count in event_counts.values()
    ):
        warnings.append(
            "The slip contains multiple props "
            "from the same game."
        )

    if any(
        count > 2
        for count in team_counts.values()
    ):
        warnings.append(
            "The slip is heavily concentrated "
            "on one team."
        )

    return warnings


def _build_selection_reason(
    *,
    player: str,
    market: str,
    prop_site: str,
    edge: int,
    confidence: int,
    side: str,
) -> str:
    reasons: list[str] = []

    if confidence >= 80:
        reasons.append(
            "very high confidence"
        )
    elif confidence >= 70:
        reasons.append(
            "strong confidence"
        )
    else:
        reasons.append(
            "qualified confidence"
        )

    if edge >= 75:
        reasons.append(
            "elite projected edge"
        )
    elif edge >= 65:
        reasons.append(
            "strong projected edge"
        )
    else:
        reasons.append(
            "positive projected edge"
        )

    readable_market = market.replace(
        "_",
        " ",
    ).title()
    return (
        f"{player} was selected for the "
        f"{side} on {readable_market} at "
        f"{prop_site} because it has "
        f"{reasons[0]} and "
        f"{reasons[1]}."
    )


def _build_risk_factors(
    *,
    candidate: PropBuilderLeg,
    selected_legs: list[PropBuilderLeg],
) -> list[str]:
    risks: list[str] = []

    same_game_count = sum(
        1
        for leg in selected_legs
        if candidate.event_id
        and leg.event_id
        == candidate.event_id
    )
    same_player_count = sum(
        1
        for leg in selected_legs
        if _normalized_key(leg.player)
        == _normalized_key(
            candidate.player
        )
    )
    same_team_count = 0
    candidate_teams = (
        _candidate_team_keys(candidate)
    )

    for leg in selected_legs:
        if candidate_teams.intersection(
            _candidate_team_keys(leg)
        ):
            same_team_count += 1

    if same_player_count > 0:
        risks.append(
            "Another prop for this player "
            "is already in the slip."
        )
    if same_game_count > 0:
        risks.append(
            "This pick is correlated with "
            "another leg from the same game."
        )
    if same_team_count >= 2:
        risks.append(
            "The slip is becoming concentrated "
            "on the same team."
        )
    if candidate.confidence < 65:
        risks.append(
            "Confidence is below the usual "
            "balanced threshold."
        )
    if candidate.edge < 60:
        risks.append(
            "Projected edge is below the usual "
            "balanced threshold."
        )

    return risks


def _matches_strategy(
    *,
    candidate: PropBuilderLeg,
    recommended_sport: str | None,
    recommended_site: str | None,
    recommended_market: str | None,
) -> bool:
    checks: list[bool] = []

    if recommended_sport:
        checks.append(
            _normalize_sport(
                candidate.sport
            )
            == _normalize_sport(
                recommended_sport
            )
        )
    if recommended_site:
        checks.append(
            normalize_prop_site(
                candidate.prop_site
            )
            == normalize_prop_site(
                recommended_site
            )
        )
    if recommended_market:
        checks.append(
            normalize_market(
                candidate.market
            )
            == normalize_market(
                recommended_market
            )
        )

    return bool(checks) and all(checks)


def _select_same_sport_legs(
    *,
    candidates: list[PropBuilderLeg],
    leg_count: int,
    same_game_allowed: bool,
    correlation_guard_enabled: bool,
    maximum_legs_per_player: int,
    maximum_legs_per_game: int,
    maximum_legs_per_team: int,
    initial_player_counts: dict[str, int] | None = None,
    initial_event_counts: dict[str, int] | None = None,
    initial_team_counts: dict[str, int] | None = None,
) -> list[PropBuilderLeg]:
    candidates_by_sport: dict[
        str,
        list[PropBuilderLeg],
    ] = {}
    for candidate in candidates:
        sport_key = _normalize_sport(
            candidate.sport
        )
        candidates_by_sport.setdefault(
            sport_key,
            [],
        ).append(candidate)

    best_selection: list[PropBuilderLeg] = []
    best_score = -1

    for sport_candidates in (
        candidates_by_sport.values()
    ):
        sport_candidates.sort(
            key=_candidate_score,
            reverse=True,
        )

        selection: list[PropBuilderLeg] = []
        player_counts = dict(initial_player_counts or {})
        event_counts = dict(initial_event_counts or {})
        team_counts = dict(initial_team_counts or {})
        effective_game_limit = (
            maximum_legs_per_game
            if same_game_allowed
            else 1
        )

        for candidate in sport_candidates:
            if not _can_add_candidate(
                candidate=candidate,
                player_counts=player_counts,
                event_counts=event_counts,
                team_counts=team_counts,
                correlation_guard_enabled=(
                    correlation_guard_enabled
                ),
                maximum_legs_per_player=(
                    maximum_legs_per_player
                ),
                maximum_legs_per_game=(
                    effective_game_limit
                ),
                maximum_legs_per_team=(
                    maximum_legs_per_team
                ),
            ):
                continue

            selection.append(candidate)
            _record_candidate(
                candidate=candidate,
                player_counts=player_counts,
                event_counts=event_counts,
                team_counts=team_counts,
            )

            if len(selection) >= leg_count:
                break

        selection_score = sum(
            leg.confidence + leg.edge
            for leg in selection
        )
        if (
            len(selection) > len(best_selection)
        ):
            best_selection = selection
            best_score = selection_score
        elif (
            len(selection) == len(best_selection)
            and selection_score > best_score
        ):
            best_selection = selection
            best_score = selection_score

    return best_selection


def _select_mixed_sport_legs(
    *,
    candidates: list[PropBuilderLeg],
    leg_count: int,
    same_game_allowed: bool,
    correlation_guard_enabled: bool,
    maximum_legs_per_player: int,
    maximum_legs_per_game: int,
    maximum_legs_per_team: int,
    initial_player_counts: dict[str, int] | None = None,
    initial_event_counts: dict[str, int] | None = None,
    initial_team_counts: dict[str, int] | None = None,
) -> list[PropBuilderLeg]:
    candidates.sort(
        key=_candidate_score,
        reverse=True,
    )

    selected: list[PropBuilderLeg] = []
    player_counts = dict(initial_player_counts or {})
    event_counts = dict(initial_event_counts or {})
    team_counts = dict(initial_team_counts or {})
    used_sports: set[str] = set()
    effective_game_limit = (
        maximum_legs_per_game
        if same_game_allowed
        else 1
    )

    # First pass: try to include different sports.
    for candidate in candidates:
        sport_key = _normalize_sport(
            candidate.sport
        )

        if sport_key in used_sports:
            continue
        if not _can_add_candidate(
            candidate=candidate,
            player_counts=player_counts,
            event_counts=event_counts,
            team_counts=team_counts,
            correlation_guard_enabled=(
                correlation_guard_enabled
            ),
            maximum_legs_per_player=(
                maximum_legs_per_player
            ),
            maximum_legs_per_game=(
                effective_game_limit
            ),
            maximum_legs_per_team=(
                maximum_legs_per_team
            ),
        ):
            continue

        selected.append(candidate)
        used_sports.add(sport_key)
        _record_candidate(
            candidate=candidate,
            player_counts=player_counts,
            event_counts=event_counts,
            team_counts=team_counts,
        )

        if len(selected) >= leg_count:
            return selected

    # Second pass: fill remaining spots with
    # the highest-rated eligible props.
    for candidate in candidates:
        if candidate in selected:
            continue

        if not _can_add_candidate(
            candidate=candidate,
            player_counts=player_counts,
            event_counts=event_counts,
            team_counts=team_counts,
            correlation_guard_enabled=(
                correlation_guard_enabled
            ),
            maximum_legs_per_player=(
                maximum_legs_per_player
            ),
            maximum_legs_per_game=(
                effective_game_limit
            ),
            maximum_legs_per_team=(
                maximum_legs_per_team
            ),
        ):
            continue

        selected.append(candidate)
        _record_candidate(
            candidate=candidate,
            player_counts=player_counts,
            event_counts=event_counts,
            team_counts=team_counts,
        )

        if len(selected) >= leg_count:
            break

    return selected


def _merge_locked_and_new_legs(
    *,
    locked_legs: list[PropBuilderLeg],
    new_legs: list[PropBuilderLeg],
    total_count: int,
) -> list[PropBuilderLeg]:
    if not locked_legs:
        return new_legs[:total_count]

    positions: list[PropBuilderLeg | None] = [
        None
        for _ in range(total_count)
    ]
    overflow_locked: list[PropBuilderLeg] = []

    for locked_leg in locked_legs:
        position = locked_leg.builder_position
        if (
            0 <= position < total_count
            and positions[position] is None
        ):
            positions[position] = locked_leg
        else:
            overflow_locked.append(locked_leg)

    remaining_legs = [
        *overflow_locked,
        *new_legs,
    ]
    remaining_index = 0

    for index in range(total_count):
        if positions[index] is not None:
            continue
        if remaining_index >= len(remaining_legs):
            break
        positions[index] = remaining_legs[remaining_index]
        remaining_index += 1

    return [
        leg
        for leg in positions
        if leg is not None
    ]


def build_prop_slip(
    *,
    request: PropBuilderRequest,
    prop_rows: list[Any],
) -> PropBuilderResponse:
    locked_legs = [
        leg.model_copy(deep=True)
        for leg in request.locked_legs
    ]
    locked_prop_ids = {
        leg.prop_id
        for leg in locked_legs
        if leg.prop_id
    }
    locked_players = {
        _normalized_key(leg.player)
        for leg in locked_legs
        if leg.player
    }
    locked_event_counts: dict[str, int] = {}
    locked_team_counts: dict[str, int] = {}
    locked_player_counts: dict[str, int] = {}
    for leg in locked_legs:
        _record_candidate(
            candidate=leg,
            player_counts=locked_player_counts,
            event_counts=locked_event_counts,
            team_counts=locked_team_counts,
        )

    risk_settings = _risk_settings(
        request.risk_mode
    )
    effective_minimum_edge = max(
        request.minimum_edge,
        int(risk_settings["minimum_edge"]),
    )
    effective_minimum_confidence = max(
        request.minimum_confidence,
        int(
            risk_settings[
                "minimum_confidence"
            ]
        ),
    )
    effective_leg_count = min(
        request.leg_count,
        int(risk_settings["maximum_legs"]),
    )
    effective_same_game_allowed = (
        request.same_game_allowed
        and bool(
            risk_settings[
                "same_game_allowed"
            ]
        )
    )

    allowed_sites = {
        normalize_prop_site(site)
        for site in request.prop_sites
    }
    selected_sports = {
        _normalize_sport(value)
        for value in request.sports
        if value.strip()
    }
    selected_markets = {
        normalize_market(value)
        for value in request.markets
        if value.strip()
    }
    excluded_prop_ids = {
        value.strip()
        for value in request.excluded_prop_ids
        if value.strip()
    }
    excluded_prop_ids.update(locked_prop_ids)

    locked_sports = {
        _normalize_sport(leg.sport)
        for leg in locked_legs
        if leg.sport
    }
    if (
        request.build_mode == "SAME_SPORT"
        and len(locked_sports) > 1
    ):
        raise ValueError(
            "Same Sport mode cannot regenerate "
            "with locked legs from multiple sports."
        )
    locked_sport = (
        next(iter(locked_sports))
        if locked_sports
        else None
    )

    remaining_leg_count = max(
        0,
        effective_leg_count - len(locked_legs),
    )

    candidates: list[PropBuilderLeg] = []
    malformed_rows = 0
    total_rows = len(prop_rows)

    for row in prop_rows:
        raw_site = _safe_text(
            _row_value(
                row,
                "sportsbook",
                _row_value(row, "prop_site", ""),
            )
        )
        prop_id = _safe_text(
            _row_value(row, "id", "")
        )
        player = _safe_text(
            _row_value(row, "player", "")
        )
        sport = _safe_text(
            _row_value(row, "sport", "")
        )
        raw_market = _safe_text(
            _row_value(row, "market", "")
        )
        if (
            not prop_id
            or not player
            or not sport
            or not raw_market
        ):
            malformed_rows += 1
            continue

        prop_site = normalize_prop_site(raw_site)
        if prop_site not in allowed_sites:
            continue

        if (
            request.build_mode == "SAME_SPORT"
            and locked_sport
            and _normalize_sport(sport)
            != locked_sport
        ):
            continue
        if (
            selected_sports
            and _normalize_sport(sport)
            not in selected_sports
        ):
            continue

        normalized_market = normalize_market(
            raw_market
        )
        if (
            selected_markets
            and normalized_market
            not in selected_markets
        ):
            continue
        if prop_id in excluded_prop_ids:
            continue
        if (
            request.correlation_guard_enabled
            and request.maximum_legs_per_player <= 1
            and _normalized_key(player)
            in locked_players
        ):
            continue

        edge = _safe_int(
            _row_value(row, "edge", 0)
        )
        confidence = _safe_int(
            _row_value(
                row,
                "confidence",
                edge,
            )
        )

        if edge < effective_minimum_edge:
            continue
        if confidence < effective_minimum_confidence:
            continue

        side, odds = _choose_side(
            row,
            request.side_preference,
        )
        line_value = _safe_float(
            _row_value(row, "line", 0)
        )
        if line_value is None:
            line_value = 0
        odds_value = _safe_int_or_none(
            _row_value(
                row,
                "odds",
                odds,
            )
        )

        candidates.append(
            PropBuilderLeg(
                prop_id=prop_id,
                event_id=_safe_text(
                    _row_value(row, "event_id", "")
                ),
                api_sports_game_id=_safe_text(
                    _row_value(
                        row,
                        "api_sports_game_id",
                        "",
                    )
                ),
                player=player,
                sport=sport,
                matchup=_safe_text(
                    _row_value(row, "matchup", "")
                ),
                prop_site=prop_site,
                market=raw_market,
                line=line_value,
                side=side,
                odds=odds_value,
                original_line=line_value,
                original_odds=odds_value,
                current_line=line_value,
                current_odds=odds_value,
                line_change=0,
                odds_change=0,
                movement_status="UNCHANGED",
                edge=edge,
                confidence=confidence,
                game_time=_safe_text(
                    _row_value(
                        row,
                        "game_time",
                        "",
                    )
                ),
                image_path=_safe_text(
                    _row_value(
                        row,
                        "image_path",
                        "",
                    )
                ),
                home_team=_safe_text(
                    _row_value(
                        row,
                        "home_team",
                        "",
                    )
                ),
                away_team=_safe_text(
                    _row_value(
                        row,
                        "away_team",
                        "",
                    )
                ),
                player_team=_safe_text(
                    _row_value(
                        row,
                        "player_team",
                        _row_value(
                            row,
                            "team",
                            "",
                        ),
                    )
                ),
            )
        )

    if request.build_mode == "MIXED_SPORTS":
        selected_new = _select_mixed_sport_legs(
            candidates=candidates,
            leg_count=remaining_leg_count,
            same_game_allowed=effective_same_game_allowed,
            correlation_guard_enabled=(
                request.correlation_guard_enabled
            ),
            maximum_legs_per_player=(
                request.maximum_legs_per_player
            ),
            maximum_legs_per_game=(
                request.maximum_legs_per_game
            ),
            maximum_legs_per_team=(
                request.maximum_legs_per_team
            ),
            initial_player_counts=locked_player_counts,
            initial_event_counts=locked_event_counts,
            initial_team_counts=locked_team_counts,
        )
    else:
        selected_new = _select_same_sport_legs(
            candidates=candidates,
            leg_count=remaining_leg_count,
            same_game_allowed=effective_same_game_allowed,
            correlation_guard_enabled=(
                request.correlation_guard_enabled
            ),
            maximum_legs_per_player=(
                request.maximum_legs_per_player
            ),
            maximum_legs_per_game=(
                request.maximum_legs_per_game
            ),
            maximum_legs_per_team=(
                request.maximum_legs_per_team
            ),
            initial_player_counts=locked_player_counts,
            initial_event_counts=locked_event_counts,
            initial_team_counts=locked_team_counts,
        )

    selected = _merge_locked_and_new_legs(
        locked_legs=locked_legs,
        new_legs=selected_new,
        total_count=effective_leg_count,
    )

    strategy = get_prop_builder_strategy()
    recommended_sport = None
    recommended_site = None
    recommended_market = None
    if strategy.enough_data:
        recommended_sport = (
            strategy.recommended_sport.name
            if strategy.recommended_sport
            else None
        )
        recommended_site = (
            strategy.recommended_prop_site.name
            if strategy.recommended_prop_site
            else None
        )
        recommended_market = (
            strategy.recommended_market.name
            if strategy.recommended_market
            else None
        )

    market_performance = (
        get_market_performance_lookup()
    )
    explained_legs: list[
        PropBuilderLeg
    ] = []
    for index, candidate in enumerate(selected):
        candidate.builder_position = index
        market_key = normalize_market(
            candidate.market
        )
        market_history = (
            market_performance.get(
                market_key,
                {},
            )
        )

        candidate.selection_reason = (
            _build_selection_reason(
                player=candidate.player,
                market=candidate.market,
                prop_site=candidate.prop_site,
                edge=candidate.edge,
                confidence=candidate.confidence,
                side=candidate.side,
            )
        )
        candidate.historical_hit_rate = (
            float(
                market_history.get(
                    "hit_rate",
                    0,
                )
            )
            if market_history
            else None
        )
        candidate.historical_sample_size = int(
            market_history.get(
                "sample_size",
                0,
            )
        )
        candidate.risk_factors = (
            _build_risk_factors(
                candidate=candidate,
                selected_legs=explained_legs,
            )
        )
        candidate.strategy_match = (
            _matches_strategy(
                candidate=candidate,
                recommended_sport=recommended_sport,
                recommended_site=recommended_site,
                recommended_market=recommended_market,
            )
        )
        explained_legs.append(candidate)

    selected = explained_legs

    available_candidate_count = len(candidates)
    filtered_out_count = max(
        0,
        total_rows - available_candidate_count,
    )
    build_messages: list[str] = []
    if malformed_rows > 0:
        build_messages.append(
            f"Skipped {malformed_rows} malformed prop row"
            f"{'s' if malformed_rows != 1 else ''}."
        )
    if available_candidate_count == 0:
        build_messages.append(
            "No candidates survived filtering for the selected sites, sports, markets, or thresholds."
        )
    elif len(selected) < effective_leg_count:
        build_messages.append(
            f"Only {len(selected)} of {effective_leg_count} requested legs were available after ranking and correlation limits."
        )

    average_edge = 0.0
    average_confidence = 0.0
    if selected:
        average_edge = round(
            sum(leg.edge for leg in selected)
            / len(selected),
            1,
        )
        average_confidence = round(
            sum(
                leg.confidence
                for leg in selected
            )
            / len(selected),
            1,
        )

    return PropBuilderResponse(
        requested_legs=request.leg_count,
        generated_legs=len(selected),
        available_candidate_count=available_candidate_count,
        filtered_out_count=filtered_out_count,
        build_messages=build_messages,
        average_edge=average_edge,
        average_confidence=average_confidence,
        prop_sites=sorted(allowed_sites),
        sports=request.sports,
        markets=request.markets,
        correlation_warnings=(
            _correlation_warnings(selected)
        ),
        build_mode=request.build_mode,
        risk_mode=request.risk_mode,
        legs=selected,
    )


def replace_prop_leg(
    *,
    request: PropReplacementRequest,
    prop_rows: list[Any],
) -> PropBuilderLeg | None:
    risk_settings = _risk_settings(
        request.risk_mode
    )
    effective_minimum_edge = max(
        request.minimum_edge,
        int(risk_settings["minimum_edge"]),
    )
    effective_minimum_confidence = max(
        request.minimum_confidence,
        int(
            risk_settings[
                "minimum_confidence"
            ]
        ),
    )

    allowed_sites = {
        normalize_prop_site(site)
        for site in request.prop_sites
    }
    selected_sports = {
        _normalize_sport(value)
        for value in request.sports
        if value.strip()
    }
    selected_markets = {
        normalize_market(value)
        for value in request.markets
        if value.strip()
    }
    excluded_prop_ids = {
        value.strip()
        for value in request.excluded_prop_ids
        if value.strip()
    }
    excluded_prop_ids.add(
        request.current_prop_id.strip()
    )
    excluded_players = {
        value.strip().lower()
        for value in request.excluded_players
        if value.strip()
    }
    excluded_event_ids = {
        value.strip()
        for value in request.excluded_event_ids
        if value.strip()
    }

    candidates: list[PropBuilderLeg] = []

    for row in prop_rows:
        prop_id = str(
            _row_value(row, "id", "")
        )
        if not prop_id:
            continue
        if prop_id in excluded_prop_ids:
            continue

        raw_site = str(
            _row_value(
                row,
                "sportsbook",
                _row_value(row, "prop_site", ""),
            )
        )
        prop_site = normalize_prop_site(raw_site)
        if prop_site not in allowed_sites:
            continue

        sport = str(
            _row_value(row, "sport", "")
        )
        if (
            selected_sports
            and _normalize_sport(sport)
            not in selected_sports
        ):
            continue

        raw_market = str(
            _row_value(row, "market", "")
        )
        normalized_market = normalize_market(
            raw_market
        )
        if (
            selected_markets
            and normalized_market
            not in selected_markets
        ):
            continue

        player = str(
            _row_value(row, "player", "")
        )
        if player.lower().strip() in excluded_players:
            continue

        event_id = str(
            _row_value(row, "event_id", "")
        )
        if (
            event_id
            and event_id in excluded_event_ids
        ):
            continue

        edge = _safe_int(
            _row_value(row, "edge", 0)
        )
        confidence = _safe_int(
            _row_value(
                row,
                "confidence",
                edge,
            )
        )

        if edge < effective_minimum_edge:
            continue
        if confidence < effective_minimum_confidence:
            continue

        side, odds = _choose_side(
            row,
            request.side_preference,
        )
        line_value = _safe_float(
            _row_value(row, "line", 0)
        )
        if line_value is None:
            line_value = 0
        odds_value = _safe_int_or_none(
            _row_value(
                row,
                "odds",
                odds,
            )
        )

        candidates.append(
            PropBuilderLeg(
                prop_id=prop_id,
                event_id=event_id,
                api_sports_game_id=str(
                    _row_value(
                        row,
                        "api_sports_game_id",
                        "",
                    )
                ),
                player=player,
                sport=sport,
                matchup=str(
                    _row_value(row, "matchup", "")
                ),
                prop_site=prop_site,
                market=raw_market,
                line=line_value,
                side=side,
                odds=odds_value,
                original_line=line_value,
                original_odds=odds_value,
                current_line=line_value,
                current_odds=odds_value,
                line_change=0,
                odds_change=0,
                movement_status="UNCHANGED",
                edge=edge,
                confidence=confidence,
                game_time=str(
                    _row_value(
                        row,
                        "game_time",
                        "",
                    )
                ),
                image_path=str(
                    _row_value(
                        row,
                        "image_path",
                        "",
                    )
                ),
                home_team=str(
                    _row_value(
                        row,
                        "home_team",
                        "",
                    )
                ),
                away_team=str(
                    _row_value(
                        row,
                        "away_team",
                        "",
                    )
                ),
                player_team=str(
                    _row_value(
                        row,
                        "player_team",
                        _row_value(
                            row,
                            "team",
                            "",
                        ),
                    )
                ),
            )
        )

    if not candidates:
        return None

    candidates.sort(
        key=lambda leg: (
            leg.confidence,
            leg.edge,
        ),
        reverse=True,
    )
    replacement = candidates[0]
    market_performance = (
        get_market_performance_lookup()
    )
    market_key = normalize_market(
        replacement.market
    )
    market_history = (
        market_performance.get(
            market_key,
            {},
        )
    )

    replacement.selection_reason = (
        _build_selection_reason(
            player=replacement.player,
            market=replacement.market,
            prop_site=replacement.prop_site,
            edge=replacement.edge,
            confidence=replacement.confidence,
            side=replacement.side,
        )
    )
    strategy = get_prop_builder_strategy()
    recommended_sport = (
        strategy.recommended_sport.name
        if strategy.enough_data and strategy.recommended_sport
        else None
    )
    recommended_site = (
        strategy.recommended_prop_site.name
        if strategy.enough_data and strategy.recommended_prop_site
        else None
    )
    recommended_market = (
        strategy.recommended_market.name
        if strategy.enough_data and strategy.recommended_market
        else None
    )
    replacement.strategy_match = _matches_strategy(
        candidate=replacement,
        recommended_sport=recommended_sport,
        recommended_site=recommended_site,
        recommended_market=recommended_market,
    )
    replacement.historical_hit_rate = (
        float(
            market_history.get(
                "hit_rate",
                0,
            )
        )
        if market_history
        else None
    )
    replacement.historical_sample_size = int(
        market_history.get(
            "sample_size",
            0,
        )
    )
    replacement.risk_factors = []
    return replacement
