import re
from datetime import datetime
from collections import defaultdict

from config import DB_PATH
from database.cache import PropCache
from models.prop import PropResponse
from services.formatters import (
	format_market_label,
	market_to_category,
	format_sport_label,
	resolve_player_image,
)
from services.time_utils import (
	format_display_time,
	parse_to_utc_iso,
	status_from_start_time,
	app_timezone,
)
from services.prop_recommendation_service import (
	build_prop_recommendation_with_fallback,
)
from services.player_identity_service import resolve_player_identity
from services.player_availability_service import (
	get_player_availability,
	adjust_confidence_for_availability,
)
from services.prop_context_service import enrich_props

cache = PropCache(DB_PATH)


def _row_optional_value(row: object, key: str) -> object:
	try:
		if key in row.keys():
			return row[key]
	except Exception:
		return None
	return None


def _make_prop_id(
	event_id: str,
	player: str,
	market: str,
	line: float,
	sportsbook: str,
) -> str:
	raw = (
		f"{event_id}-{player}-{market}-{line}-{sportsbook}"
	).lower()
	return re.sub(r"[^a-z0-9]+", "-", raw).strip("-")


def _make_player_id(player: str) -> str:
	raw = player.lower()
	return re.sub(r"[^a-z0-9]+", "-", raw).strip("-")


def _american_to_decimal(odds: float | None) -> float | None:
	if odds is None:
		return None
	if odds > 0:
		return round(1 + (odds / 100), 4)
	if odds < 0:
		return round(1 + (100 / abs(odds)), 4)
	return None


def _american_to_implied_probability(odds: float | None) -> float | None:
	if odds is None:
		return None
	if odds > 0:
		return round(100 / (odds + 100), 6)
	if odds < 0:
		return round(abs(odds) / (abs(odds) + 100), 6)
	return None


def _normalize_game_status(raw_status: object, start_time_utc: str) -> str:
	raw = str(raw_status or "").strip().lower()
	if raw:
		if "postpon" in raw:
			return "postponed"
		if "cancel" in raw:
			return "canceled"
		if "delay" in raw:
			return "delayed"
		if raw in {"final", "completed", "closed"}:
			return "final"
		if raw in {"in_progress", "live", "ongoing"}:
			return "live"
		if raw in {"scheduled", "not_started", "upcoming"}:
			return "scheduled"

	fallback = status_from_start_time(start_time_utc).strip().lower()
	if fallback == "live":
		return "live"
	return "scheduled"


def _tier_from_confidence(confidence: int, side: str) -> str:
	if side.upper() not in {"OVER", "UNDER"}:
		return "No Pick"
	if confidence >= 65:
		return "Premium"
	if confidence >= 60:
		return "Strong"
	if confidence >= 57:
		return "Lean"
	return "Pass"


def get_props() -> list[PropResponse]:
	rows = cache.load_props()
	results: list[PropResponse] = []
	matchup_key_games: dict[str, set[str]] = defaultdict(set)
	local_tz = app_timezone()

	for row in rows:
		home_team = str(row["home_team"] or "")
		away_team = str(row["away_team"] or "")
		start_time_utc = parse_to_utc_iso(
			row["commence_time"]
		)
		start_dt = (
			datetime.fromisoformat(start_time_utc.replace("Z", "+00:00"))
			if start_time_utc
			else None
		)
		local_date = (
			start_dt.astimezone(local_tz).date().isoformat()
			if start_dt is not None
			else ""
		)
		matchup_key = (
			f"{str(row['sport']).upper()}|"
			f"{away_team.strip().upper()}|"
			f"{home_team.strip().upper()}|"
			f"{local_date}"
		)
		game_id = str(row["game_id"] or "")
		if game_id:
			matchup_key_games[matchup_key].add(game_id)

	for row in rows:
		player = str(row["player_name"])
		raw_market = str(row["prop_type"])
		sportsbook = str(row["bookmaker"] or "")
		line = float(row["line"])
		confidence = int(round(float(row["confidence"] or 0)))
		home_team = str(row["home_team"] or "")
		away_team = str(row["away_team"] or "")
		matchup = f"{away_team} @ {home_team}".strip()
		start_time_utc = parse_to_utc_iso(
			row["commence_time"]
		)
		start_dt = (
			datetime.fromisoformat(start_time_utc.replace("Z", "+00:00"))
			if start_time_utc
			else None
		)
		local_start = (
			start_dt.astimezone(local_tz)
			if start_dt is not None
			else None
		)
		local_date_text = (
			local_start.date().isoformat()
			if local_start is not None
			else ""
		)
		display_time = format_display_time(start_time_utc)
		projection = _row_optional_value(row, "projection")
		if projection is None:
			projection = _row_optional_value(
				row,
				"projected_value",
			)
		if projection is None:
			projection = _row_optional_value(
				row,
				"model_projection",
			)
		recommendation = build_prop_recommendation_with_fallback(
			projection=projection,
			line=line,
			odds_pick=str(row["prediction"] or "UNDER"),
			odds_confidence=confidence,
		)
		recommended_side = str(
			recommendation["recommendedSide"]
		)
		recommended_pick = (
			recommended_side.upper()
			if recommended_side.upper() in {"OVER", "UNDER"}
			else str(row["prediction"] or "UNDER").upper()
		)
		source_player_id = str(row["source_player_id"] or "")
		identity = resolve_player_identity(
			source_provider="odds-api",
			source_player_id=source_player_id,
			player_name=player,
		)
		canonical_player_id = str(identity.get("canonical_player_id") or "")
		if not canonical_player_id:
			canonical_player_id = _make_player_id(player)
		injury_status, lineup_status = get_player_availability(
			canonical_player_id=canonical_player_id,
		)
		adjusted_confidence = adjust_confidence_for_availability(
			base_confidence=int(recommendation["confidence"]),
			injury_status=injury_status,
			lineup_status=lineup_status,
		)
		adjusted_tier = _tier_from_confidence(
			adjusted_confidence,
			recommended_side,
		)
		edge_signed = 0.0
		if projection is not None:
			try:
				edge_signed = round(float(projection) - line, 4)
			except Exception:
				edge_signed = 0.0

		over_odds = row["over_odds"]
		under_odds = row["under_odds"]
		opening_line = row["opening_line"]
		current_line = row["current_line"]
		line_moved_at = str(row["line_updated_at"] or "")
		over_implied = _american_to_implied_probability(over_odds)
		under_implied = _american_to_implied_probability(under_odds)
		no_vig_over = None
		no_vig_under = None
		if over_implied is not None and under_implied is not None:
			total = over_implied + under_implied
			if total > 0:
				no_vig_over = round(over_implied / total, 6)
				no_vig_under = round(under_implied / total, 6)

		source_game_status = _normalize_game_status(
			row["game_status"],
			start_time_utc,
		)
		is_doubleheader = False
		matchup_key = (
			f"{str(row['sport']).upper()}|"
			f"{away_team.strip().upper()}|"
			f"{home_team.strip().upper()}|"
			f"{local_date_text}"
		)
		if len(matchup_key_games.get(matchup_key, set())) > 1:
			is_doubleheader = True

		updated_at = str(row["updated_at"] or "")
		sport_label = format_sport_label(str(row["sport"]))

		results.append(
			PropResponse(
				id=_make_prop_id(
					str(row["game_id"]),
					player,
					raw_market,
					line,
					sportsbook,
				),
				gameId=str(row["game_id"]),
				eventId=str(row["game_id"]),
				apiSportsGameId=str(
					row["api_sports_game_id"] or ""
				),
				playerId=canonical_player_id,
				sourcePlayerId=source_player_id,
				canonicalPlayerId=canonical_player_id,
				playerIdentityConfidence=float(
					identity.get("confidence") or 0.0
				),
				player=player,
				sport=sport_label,
				matchup=matchup,
				sportsbook=sportsbook.upper(),
				category=market_to_category(raw_market),
				market=format_market_label(raw_market),
				marketKey=raw_market,
				line=line,
				openingLine=float(opening_line) if isinstance(opening_line, (int, float)) else line,
				currentLine=float(current_line) if isinstance(current_line, (int, float)) else line,
				lineMovedAtUtc=line_moved_at,
				projection=projection,
				pick=recommended_pick,
				edge=float(
					recommendation["edge"]
				),
				edgeSigned=edge_signed,
				recommendedSide=recommendation[
					"recommendedSide"
				],
				confidence=adjusted_confidence,
				recommendationEdge=recommendation[
					"edge"
				],
				tier=adjusted_tier,
				pickText=recommendation["pickText"],
				startTimeUtc=start_time_utc,
				displayTime=display_time,
				gameStatus=source_game_status,
				sourceGameStatus=source_game_status,
				gameTime=display_time,
				gameStartTime=start_time_utc,
				gameDateLocal=local_date_text,
				timezone=str(local_tz),
				isDoubleheader=is_doubleheader,
				isNeutralSite=False,
				isCanceled=source_game_status == "canceled",
				isDelayed=source_game_status == "delayed",
				lastUpdatedUtc=updated_at,
				sourceUpdatedUtc=updated_at,
				sourceProvider="odds-api",
				injuryStatus=injury_status,
				lineupStatus=lineup_status,
				imagePath=resolve_player_image(player, sport_label),
				overOdds=over_odds,
				underOdds=under_odds,
				overDecimalOdds=_american_to_decimal(over_odds),
				underDecimalOdds=_american_to_decimal(under_odds),
				overImpliedProbability=over_implied,
				underImpliedProbability=under_implied,
				noVigOverProbability=no_vig_over,
				noVigUnderProbability=no_vig_under,
			)
		)

	enrich_props(results)
	return results
