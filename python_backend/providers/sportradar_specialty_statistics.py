"""Completed Tennis and UFC statistics from licensed Sportradar feeds.

These feeds supplement ESPN only when ESPN has no completed rows for the
sport/date. That prevents one match from being counted twice in projections.
"""

from __future__ import annotations

from datetime import date
import hashlib
from typing import Any

import requests

from config import (
    HTTP_TIMEOUT_SECONDS,
    SPORTRADAR_ACCESS_LEVEL,
    SPORTRADAR_API_KEY,
)

BASE = "https://api.sportradar.com"


def configured() -> bool:
    return bool(SPORTRADAR_API_KEY)


def _id(sport: str, event: object, player: object) -> str:
    return hashlib.sha256(f"{sport}|{event}|{player}".encode()).hexdigest()[:32]


def _number(value: object) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def _daily_summaries(sport: str, version: str, target: date) -> dict[str, Any]:
    response = requests.get(
        f"{BASE}/{sport}/{SPORTRADAR_ACCESS_LEVEL}/{version}/en/"
        f"schedules/{target.isoformat()}/summaries.json",
        headers={"accept": "application/json", "x-api-key": SPORTRADAR_API_KEY},
        params={"limit": 200},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    return payload if isinstance(payload, dict) else {}


def _get(path: str) -> dict[str, Any]:
    response = requests.get(
        f"{BASE}/{path.lstrip('/')}",
        headers={"accept": "application/json", "x-api-key": SPORTRADAR_API_KEY},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    return payload if isinstance(payload, dict) else {}


def _competitor_stats(summary: dict[str, Any]) -> dict[str, dict[str, Any]]:
    statistics = summary.get("statistics")
    statistics = statistics if isinstance(statistics, dict) else {}
    totals = statistics.get("totals")
    totals = totals if isinstance(totals, dict) else {}
    competitors = totals.get("competitors")
    if not isinstance(competitors, list):
        competitors = statistics.get("competitors")
    result: dict[str, dict[str, Any]] = {}
    for row in competitors if isinstance(competitors, list) else []:
        if not isinstance(row, dict):
            continue
        identifier = str(row.get("id") or "")
        values = row.get("statistics")
        if identifier and isinstance(values, dict):
            result[identifier] = values
    return result


def normalize_tennis_summaries(
    payload: object, *, target_date: date,
) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    rows: list[dict[str, object]] = []
    for summary in root.get("summaries", []) if isinstance(root.get("summaries"), list) else []:
        if not isinstance(summary, dict):
            continue
        event = summary.get("sport_event")
        status = summary.get("sport_event_status")
        event = event if isinstance(event, dict) else {}
        status = status if isinstance(status, dict) else {}
        if str(status.get("status") or "").lower() not in {"ended", "closed"}:
            continue
        event_id = str(event.get("id") or "")
        competitors = event.get("competitors")
        period_scores = status.get("period_scores")
        stats_by_id = _competitor_stats(summary)
        context = event.get("sport_event_context")
        context = context if isinstance(context, dict) else {}
        category = context.get("category")
        league = str(category.get("name") or "TENNIS") if isinstance(category, dict) else "TENNIS"
        winner_id = str(status.get("winner_id") or "")
        for competitor in competitors if isinstance(competitors, list) else []:
            if not isinstance(competitor, dict):
                continue
            player_id = str(competitor.get("id") or "")
            qualifier = str(competitor.get("qualifier") or "").lower()
            home = qualifier == "home"
            games_won = 0.0
            sets_won = 0.0
            for period in period_scores if isinstance(period_scores, list) else []:
                if not isinstance(period, dict):
                    continue
                own = _number(period.get("home_score" if home else "away_score"))
                other = _number(period.get("away_score" if home else "home_score"))
                games_won += own
                sets_won += float(own > other)
            values = stats_by_id.get(player_id, {})
            rows.append({
                "id": _id("TENNIS", event_id, player_id),
                "sport": "TENNIS", "league": league.upper(),
                "event_id": event_id, "player_id": player_id,
                "player_name": str(competitor.get("name") or ""),
                "team_id": "", "game_date": target_date,
                "stats": {
                    "sets_won": sets_won,
                    "games_won": games_won,
                    "match_win": float(player_id == winner_id),
                    "aces": _number(values.get("aces")),
                    "double_faults": _number(values.get("double_faults")),
                    "breakpoints_won": _number(values.get("breakpoints_won")),
                },
                "source": "SPORTRADAR", "raw": summary,
            })
    return [row for row in rows if row["event_id"] and row["player_id"] and row["player_name"]]


def tennis_logs(*, target_date: date) -> list[dict[str, object]]:
    return normalize_tennis_summaries(
        _daily_summaries("tennis", "v3", target_date),
        target_date=target_date,
    )


def normalize_mma_summaries(
    payload: object, *, target_date: date,
) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    rows: list[dict[str, object]] = []
    for summary in root.get("summaries", []) if isinstance(root.get("summaries"), list) else []:
        if not isinstance(summary, dict):
            continue
        event = summary.get("sport_event")
        status = summary.get("sport_event_status")
        event = event if isinstance(event, dict) else {}
        status = status if isinstance(status, dict) else {}
        if str(status.get("status") or "").lower() not in {"ended", "closed"}:
            continue
        event_id = str(event.get("id") or "")
        winner_id = str(status.get("winner_id") or "")
        stats_by_id = _competitor_stats(summary)
        final_round = max(1, int(_number(status.get("final_round")) or 1))
        length = str(status.get("final_round_length") or "0:00")
        try:
            minutes, seconds = (int(piece) for piece in length.split(":", 1))
        except (TypeError, ValueError):
            minutes, seconds = 0, 0
        fight_time = float((final_round - 1) * 300 + minutes * 60 + seconds)
        competitors = event.get("competitors")
        for competitor in competitors if isinstance(competitors, list) else []:
            if not isinstance(competitor, dict):
                continue
            player_id = str(competitor.get("id") or "")
            values = stats_by_id.get(player_id, {})
            rows.append({
                "id": _id("UFC", event_id, player_id),
                "sport": "UFC", "league": "UFC", "event_id": event_id,
                "player_id": player_id,
                "player_name": str(competitor.get("name") or ""),
                "team_id": "", "game_date": target_date,
                "stats": {
                    "significant_strikes": _number(values.get("significant_strikes")),
                    "total_strikes": _number(values.get("total_strikes")),
                    "takedowns": _number(values.get("takedowns")),
                    "knockdowns": _number(values.get("knockdowns")),
                    "submission_attempts": _number(values.get("submission_attempts")),
                    "fight_time_seconds": fight_time,
                    "fight_win": float(player_id == winner_id),
                },
                "source": "SPORTRADAR", "raw": summary,
            })
    return [row for row in rows if row["event_id"] and row["player_id"] and row["player_name"]]


def ufc_logs(*, target_date: date) -> list[dict[str, object]]:
    return normalize_mma_summaries(
        _daily_summaries("mma", "v2", target_date),
        target_date=target_date,
    )


def normalize_golf_leaderboard(
    payload: object, *, target_date: date, tournament_id: str,
    round_number: int | None = None,
) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    leaderboard = root.get("leaderboard")
    if not isinstance(leaderboard, list):
        tournament = root.get("tournament")
        tournament = tournament if isinstance(tournament, dict) else {}
        leaderboard = tournament.get("leaderboard")
    rows: list[dict[str, object]] = []
    for entry in leaderboard if isinstance(leaderboard, list) else []:
        if not isinstance(entry, dict):
            continue
        player = entry.get("player") if isinstance(entry.get("player"), dict) else entry
        player_id = str(player.get("id") or entry.get("id") or "")
        player_name = str(
            player.get("name")
            or " ".join(filter(None, (player.get("first_name"), player.get("last_name"))))
        ).strip()
        rounds = entry.get("rounds")
        if not isinstance(rounds, list):
            rounds = entry.get("round") if isinstance(entry.get("round"), list) else []
        for round_row in rounds:
            if not isinstance(round_row, dict):
                continue
            sequence = int(_number(round_row.get("sequence") or round_row.get("number")))
            if round_number is not None and sequence != round_number:
                continue
            event_id = f"{tournament_id}-r{sequence}"
            rows.append({
                "id": _id("PGA", event_id, player_id),
                "sport": "PGA", "league": "PGA", "event_id": event_id,
                "player_id": player_id, "player_name": player_name,
                "team_id": "", "game_date": target_date,
                "stats": {
                    "round_score": _number(round_row.get("strokes")),
                    "birdies": _number(round_row.get("birdies")),
                    "bogeys": _number(round_row.get("bogeys")),
                    "pars": _number(round_row.get("pars")),
                    "eagles": _number(round_row.get("eagles")),
                },
                "source": "SPORTRADAR", "raw": round_row,
            })
    return [row for row in rows if row["player_id"] and row["player_name"]]


def golf_logs(*, target_date: date, tour: str = "pga") -> list[dict[str, object]]:
    schedule = _get(
        f"golf/{SPORTRADAR_ACCESS_LEVEL}/{tour}/v3/en/{target_date.year}/"
        "tournaments/schedule.json"
    )
    tournaments = schedule.get("tournaments")
    rows: list[dict[str, object]] = []
    for tournament in tournaments if isinstance(tournaments, list) else []:
        if not isinstance(tournament, dict):
            continue
        start_text = str(tournament.get("start_date") or "")[:10]
        end_text = str(tournament.get("end_date") or start_text)[:10]
        try:
            start_date = date.fromisoformat(start_text)
            end_date = date.fromisoformat(end_text)
        except ValueError:
            continue
        if not start_date <= target_date <= end_date:
            continue
        tournament_id = str(tournament.get("id") or "")
        if not tournament_id:
            continue
        leaderboard = _get(
            f"golf/{SPORTRADAR_ACCESS_LEVEL}/{tour}/v3/en/{target_date.year}/"
            f"tournaments/{tournament_id}/leaderboard.json"
        )
        expected_round = (target_date - start_date).days + 1
        rows.extend(normalize_golf_leaderboard(
            leaderboard, target_date=target_date,
            tournament_id=tournament_id, round_number=expected_round,
        ))
    return rows
