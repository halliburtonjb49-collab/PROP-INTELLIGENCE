"""ESPN box-score ingestion for NFL and NHL player game logs.

Both leagues use the same site feed as the basketball provider: a scoreboard
call lists completed events, and a summary call per event returns players
grouped into statistic sections. Only the sport path and the stat keys differ,
so the fetching lives here once and each league contributes a mapping.

Box scores are the floor, not the ceiling. They carry targets, receptions,
carries, ice time and shots -- enough for the opportunity decompositions --
but not routes run, separation, air yards or zone time, which need a tracking
feed.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Iterable, Mapping

import requests

from config import HTTP_TIMEOUT_SECONDS

_BASE_URL = "https://site.api.espn.com/apis/site/v2/sports"


def _number(value: object) -> float | None:
    text = str(value if value is not None else "").strip()
    if not text or text in {"-", "--"}:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _first_of_pair(value: object) -> float | None:
    """Left side of an ESPN "made/attempted" or "made-attempted" pair."""

    text = str(value if value is not None else "").strip()
    if not text:
        return None
    for separator in ("/", "-"):
        if separator in text:
            return _number(text.split(separator, 1)[0])
    return _number(text)


def _second_of_pair(value: object) -> float | None:
    text = str(value if value is not None else "").strip()
    for separator in ("/", "-"):
        if separator in text:
            parts = text.split(separator, 1)
            return _number(parts[1]) if len(parts) == 2 else None
    return None


def _minutes_from_clock(value: object) -> float | None:
    """Convert an "18:24" ice-time string to minutes as a decimal.

    Returned as minutes rather than seconds because every rate downstream is
    expressed per minute.
    """

    text = str(value if value is not None else "").strip()
    if not text:
        return None
    if ":" not in text:
        return _number(text)
    minutes, _, seconds = text.partition(":")
    whole = _number(minutes)
    part = _number(seconds)
    if whole is None:
        return None
    return round(whole + ((part or 0.0) / 60.0), 4)


@dataclass(frozen=True)
class StatMapping:
    """How one ESPN statistic section maps into canonical stat names."""

    # ESPN's key -> our stat name, read directly as a number.
    direct: Mapping[str, str] = field(default_factory=dict)
    # ESPN's key -> our stat name, taking the left side of a pair.
    first_of_pair: Mapping[str, str] = field(default_factory=dict)
    # ESPN's key -> our stat name, taking the right side of a pair.
    second_of_pair: Mapping[str, str] = field(default_factory=dict)
    # ESPN's key -> our stat name, parsed from a mm:ss clock.
    clock: Mapping[str, str] = field(default_factory=dict)


# Section names ESPN uses, mapped to the stats each one carries. Sections not
# listed are ignored rather than guessed at.
NFL_SECTIONS: Mapping[str, StatMapping] = {
    "passing": StatMapping(
        direct={
            "passingYards": "passing_yards",
            "passingTouchdowns": "passing_touchdowns",
            "interceptions": "interceptions_thrown",
        },
        first_of_pair={"completions/passingAttempts": "completions"},
        second_of_pair={"completions/passingAttempts": "pass_attempts"},
    ),
    "rushing": StatMapping(
        direct={
            "rushingAttempts": "carries",
            "rushingYards": "rushing_yards",
            "rushingTouchdowns": "rushing_touchdowns",
        },
    ),
    "receiving": StatMapping(
        direct={
            "receptions": "receptions",
            "receivingYards": "receiving_yards",
            "receivingTouchdowns": "receiving_touchdowns",
            "receivingTargets": "targets",
        },
    ),
}

NHL_SECTIONS: Mapping[str, StatMapping] = {
    "forwards": StatMapping(
        direct={
            "goals": "goals",
            "assists": "assists",
            "points": "points",
            "shotsTotal": "shots_on_goal",
            "blockedShots": "blocked_shots",
            "hits": "hits",
        },
        clock={
            "timeOnIce": "time_on_ice",
            "powerPlayTimeOnIce": "power_play_time_on_ice",
            "shortHandedTimeOnIce": "short_handed_time_on_ice",
            "evenTimeOnIce": "even_time_on_ice",
        },
    ),
    "goalies": StatMapping(
        direct={
            "saves": "saves",
            "shotsAgainst": "shots_against",
            "goalsAgainst": "goals_against",
        },
        clock={"timeOnIce": "time_on_ice"},
    ),
}
# Defencemen record the same statistics as forwards.
NHL_SECTIONS = {**NHL_SECTIONS, "defenses": NHL_SECTIONS["forwards"]}


@dataclass(frozen=True)
class LeagueConfig:
    path: str
    sections: Mapping[str, StatMapping]


LEAGUES: Mapping[str, LeagueConfig] = {
    "NFL": LeagueConfig(path="football/nfl", sections=NFL_SECTIONS),
    "NHL": LeagueConfig(path="hockey/nhl", sections=NHL_SECTIONS),
}


def extract_section_stats(
    section: Mapping[str, object],
    mapping: StatMapping,
) -> dict[str, dict[str, float]]:
    """Pull one statistics section into {athlete id: {stat: value}}.

    Athletes who did not play are skipped rather than recorded as zeros: a
    healthy scratch is missing data, and a zero would drag every rate down.
    """

    keys = section.get("keys")
    athletes = section.get("athletes")
    if not isinstance(keys, list) or not isinstance(athletes, list):
        return {}

    extracted: dict[str, dict[str, float]] = {}
    for item in athletes:
        if not isinstance(item, dict) or item.get("didNotPlay") is True:
            continue
        athlete = item.get("athlete")
        values = item.get("stats")
        if not isinstance(athlete, dict) or not isinstance(values, list):
            continue
        athlete_id = str(athlete.get("id") or "").strip()
        if not athlete_id:
            continue
        raw = {
            str(key): values[index] if index < len(values) else None
            for index, key in enumerate(keys)
        }
        stats: dict[str, float] = {}
        for source, target in mapping.direct.items():
            value = _number(raw.get(source))
            if value is not None:
                stats[target] = value
        for source, target in mapping.first_of_pair.items():
            value = _first_of_pair(raw.get(source))
            if value is not None:
                stats[target] = value
        for source, target in mapping.second_of_pair.items():
            value = _second_of_pair(raw.get(source))
            if value is not None:
                stats[target] = value
        for source, target in mapping.clock.items():
            value = _minutes_from_clock(raw.get(source))
            if value is not None:
                stats[target] = value
        if stats:
            extracted[athlete_id] = stats
    return extracted


def parse_event_summary(
    summary: Mapping[str, object],
    *,
    sport: str,
) -> list[dict[str, object]]:
    """Merge every statistics section of one event into per-player rows.

    A quarterback appears in both the passing and rushing sections; the
    sections are merged per athlete so he yields one row, not two.
    """

    config = LEAGUES.get(str(sport).upper())
    if config is None:
        return []
    boxscore = summary.get("boxscore")
    teams = boxscore.get("players", []) if isinstance(boxscore, dict) else []

    rows: list[dict[str, object]] = []
    for team_box in teams if isinstance(teams, list) else []:
        if not isinstance(team_box, dict):
            continue
        team = team_box.get("team")
        team_id = str(team.get("id") or "") if isinstance(team, dict) else ""
        merged: dict[str, dict[str, object]] = {}
        sections = team_box.get("statistics")
        for section in sections if isinstance(sections, list) else []:
            if not isinstance(section, dict):
                continue
            mapping = config.sections.get(str(section.get("name") or ""))
            if mapping is None:
                continue
            names = {
                str(item.get("athlete", {}).get("id") or ""): str(
                    item.get("athlete", {}).get("displayName")
                    or item.get("athlete", {}).get("fullName")
                    or ""
                )
                for item in section.get("athletes", [])
                if isinstance(item, dict) and isinstance(item.get("athlete"), dict)
            }
            for athlete_id, stats in extract_section_stats(section, mapping).items():
                entry = merged.setdefault(
                    athlete_id,
                    {
                        "player_id": athlete_id,
                        "player_name": names.get(athlete_id, ""),
                        "team_id": team_id,
                        "stats": {},
                    },
                )
                if not entry["player_name"]:
                    entry["player_name"] = names.get(athlete_id, "")
                entry["stats"].update(stats)
        rows.extend(
            entry for entry in merged.values() if entry["stats"] and entry["player_name"]
        )
    return rows


class EspnBoxScoreStatisticsProvider:
    """Fetch completed daily NFL or NHL player box scores from ESPN."""

    def _json(self, url: str, *, params: dict[str, object]) -> dict:
        response = requests.get(
            url,
            params=params,
            headers={
                "Accept": "application/json",
                "User-Agent": (
                    "Mozilla/5.0 (compatible; PropsIntell/1.0; "
                    "+https://propsintell.com)"
                ),
            },
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
        return payload if isinstance(payload, dict) else {}

    def _event_logs(
        self,
        *,
        sport: str,
        config: LeagueConfig,
        target_date: date,
        event: Mapping[str, object],
    ) -> Iterable[dict[str, object]]:
        event_id = str(event.get("id") or "").strip()
        if not event_id:
            return []
        summary = self._json(
            f"{_BASE_URL}/{config.path}/summary",
            params={"event": event_id},
        )
        rows = parse_event_summary(summary, sport=sport)
        for row in rows:
            row["sport"] = sport
            row["event_id"] = event_id
            row["game_date"] = target_date.isoformat()
            row["matchup"] = str(event.get("name") or "")
            row["source"] = "ESPN"
        return rows

    def daily_game_logs(
        self,
        *,
        sport: str,
        target_date: date,
    ) -> list[dict[str, object]]:
        normalized_sport = str(sport).upper()
        config = LEAGUES.get(normalized_sport)
        if config is None:
            return []
        payload = self._json(
            f"{_BASE_URL}/{config.path}/scoreboard",
            params={"dates": target_date.strftime("%Y%m%d"), "limit": 100},
        )
        rows: list[dict[str, object]] = []
        for event in payload.get("events", []):
            if not isinstance(event, dict):
                continue
            status = event.get("status")
            status_type = status.get("type") if isinstance(status, dict) else {}
            if (
                not isinstance(status_type, dict)
                or status_type.get("completed") is not True
            ):
                continue
            rows.extend(
                self._event_logs(
                    sport=normalized_sport,
                    config=config,
                    target_date=target_date,
                    event=event,
                )
            )
        return rows
