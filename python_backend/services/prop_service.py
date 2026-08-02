import re
import os
from statistics import median
from datetime import datetime, timezone
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
	build_verified_prop_recommendation,
)
from services.player_identity_service import resolve_player_identity
from services.player_availability_service import (
	get_player_availability,
	adjust_confidence_for_availability,
)
from services.prop_context_service import enrich_props
from services.mlb_headshot_service import mlb_player_id
from services.espn_headshot_service import espn_player_id
from services.baseline_projection_service import (
	baseline_is_actionable,
	baseline_projection_for_prop,
)
from services.projection_calibration_service import (
	calibrated_hit_probability,
	confidence_from_probability,
	market_volatility_floor,
)
from services.prop_probability_service import evaluate_market, shin_method_devig
from services.market_calibration_service import market_calibration_adjustment

cache = PropCache(DB_PATH)


def data_freshness(
	updated_at: object,
	now_utc: datetime | None = None,
) -> tuple[int | None, bool]:
	"""Return source age and fail closed when freshness cannot be verified."""
	raw = str(updated_at or "").strip()
	if not raw:
		return None, True
	try:
		parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
	except ValueError:
		return None, True
	if parsed.tzinfo is None:
		parsed = parsed.replace(tzinfo=timezone.utc)
	now = now_utc or datetime.now(timezone.utc)
	age_seconds = max(0, int((now - parsed.astimezone(timezone.utc)).total_seconds()))
	stale_after = max(300, int(os.getenv("PROP_FEED_STALE_MINUTES", "45")) * 60)
	return age_seconds, age_seconds > stale_after


def _row_optional_value(row: object, key: str) -> object:
	try:
		if key in row.keys():
			return row[key]
	except Exception:
		return None
	return None


def market_snapshot(rows: list[object], fallback_line: float) -> dict[str, object]:
	"""Build an honest cross-book snapshot without inventing unavailable volume."""
	lines = [float(row["line"]) for row in rows]
	books = {
		str(row["bookmaker"] or "").strip().lower()
		for row in rows
		if str(row["bookmaker"] or "").strip()
	}
	over_prices = [
		(float(row["over_odds"]), str(row["bookmaker"] or ""))
		for row in rows
		if isinstance(row["over_odds"], (int, float))
	]
	under_prices = [
		(float(row["under_odds"]), str(row["bookmaker"] or ""))
		for row in rows
		if isinstance(row["under_odds"], (int, float))
	]
	return {
		"origin_line": median(lines) if lines else fallback_line,
		"book_count": len(books),
		"best_over": max(over_prices, default=(None, ""), key=lambda value: value[0] or -100000),
		"best_under": max(under_prices, default=(None, ""), key=lambda value: value[0] or -100000),
	}


def _make_prop_id(
	event_id: str,
	player: str,
	market: str,
	line: float,
	sportsbook: str,
) -> str:
	# The line is intentionally excluded. A site's number can move while the
	# underlying event/player/market/site prop remains the same selection.
	# Stable ids let cards, watchlists, and active slips receive that update.
	raw = (
		f"{event_id}-{player}-{market}-{sportsbook}"
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
	market_groups: dict[tuple[str, str, str, str], list[object]] = defaultdict(list)
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
		market_groups[(
			str(row["sport"]).strip().lower(),
			game_id,
			str(row["player_name"]).strip().lower(),
			str(row["prop_type"]).strip().lower(),
		)].append(row)

	for row in rows:
		player = str(row["player_name"])
		raw_market = str(row["prop_type"])
		sportsbook = str(row["bookmaker"] or "")
		line = float(row["line"])
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
		projection_source = ""
		projection_model_version = ""
		projection_sample_size = 0
		projection_volatility = None
		projection_calibrated = False
		projection_label = ""
		historical_hit_rate = None
		hit_probability = None
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
		if projection is not None:
			projection_source = "provider"
			projection_model_version = "provider-projection-v1"
			projection_label = "Provider projection"
		source_player_id = str(row["source_player_id"] or "")
		identity_provider = "odds-api"
		if not source_player_id and str(row["sport"]).lower() == "baseball_mlb":
			official_mlb_id = mlb_player_id(player)
			if official_mlb_id is not None:
				source_player_id = str(official_mlb_id)
				identity_provider = "mlb"
		if not source_player_id:
			official_espn_id = espn_player_id(
				player,
				format_sport_label(str(row["sport"])),
			)
			if official_espn_id:
				source_player_id = official_espn_id
				identity_provider = "espn"
		identity = resolve_player_identity(
			source_provider=identity_provider,
			source_player_id=source_player_id,
			player_name=player,
			identity_scope=str(row["sport"] or ""),
		)
		canonical_player_id = str(identity.get("canonical_player_id") or "")
		if not canonical_player_id:
			canonical_player_id = _make_player_id(player)
		identity_confidence = float(
			identity.get("confidence") or 0.0
		)
		sport_label = format_sport_label(str(row["sport"]))
		baseline = None
		if projection is None and identity_confidence >= 0.8:
			baseline = baseline_projection_for_prop(
				sport=sport_label,
				player=player,
				player_id=source_player_id or canonical_player_id,
				market=raw_market,
				line=line,
			)
			if baseline is not None:
				projection = baseline.projection
				projection_source = baseline.source
				projection_model_version = baseline.model_version
				projection_sample_size = baseline.sample_size
				projection_volatility = baseline.volatility
				projection_calibrated = baseline.calibrated
				projection_label = "Baseline historical model"
				historical_hit_rate = baseline.historical_hit_rate
				hit_probability = baseline.hit_probability
		confidence_override = baseline.confidence if baseline is not None else None
		if projection is not None and baseline is None and float(projection) != line:
			provider_side = "OVER" if float(projection) > line else "UNDER"
			hit_probability = calibrated_hit_probability(
				projection=float(projection),
				line=line,
				volatility=market_volatility_floor(sport_label, raw_market),
				side=provider_side,
				sample_size=8,
				sport=sport_label,
				market=raw_market,
			)
			confidence_override = confidence_from_probability(hit_probability)
		recommendation = build_verified_prop_recommendation(
			projection=projection,
			line=line,
			canonical_player_id=canonical_player_id,
			identity_confidence=identity_confidence,
			confidence_override=confidence_override,
			data_quality_score=(
				min(
					1.0,
					0.35
					+ (0.25 if identity_confidence >= 0.8 else 0.0)
					+ (0.2 if projection is not None else 0.0)
					+ (0.2 if baseline is None or projection_sample_size >= 5 else 0.0),
				)
			),
			data_quality_reasons=(
				[]
				if baseline is None or projection_sample_size >= 5
				else ["limited_historical_sample"]
			),
		)
		if baseline is not None and not baseline_is_actionable(
			baseline,
			recommendation_tier=str(recommendation["tier"]),
		):
			recommendation.update(
				{
					"recommendedSide": "N/A",
					"pickText": "No Pick",
					"recommendationAvailable": False,
					"recommendationUnavailableReason": "model_signal_below_threshold",
				}
			)
		recommended_side = str(
			recommendation["recommendedSide"]
		)
		recommended_pick = (
			recommended_side.upper()
			if recommended_side.upper() in {"OVER", "UNDER"}
			else "N/A"
		)
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
			no_vig_over, no_vig_under = shin_method_devig(
				over_implied,
				under_implied,
			)
		market_evaluation = None
		evaluation_side = recommended_pick
		if (
			projection is not None
			and evaluation_side not in {"OVER", "UNDER"}
			and float(projection) != line
		):
			evaluation_side = "OVER" if float(projection) > line else "UNDER"
		calibration_adjustment, calibration_sample_size = (
			market_calibration_adjustment(
				sport_label,
				raw_market,
				projection_model_version,
				evaluation_side,
			)
		)
		if projection is not None and evaluation_side in {"OVER", "UNDER"}:
			selected_market_probability = (
				no_vig_over if evaluation_side == "OVER" else no_vig_under
			)
			selected_decimal_odds = (
				_american_to_decimal(over_odds)
				if evaluation_side == "OVER"
				else _american_to_decimal(under_odds)
			)
			market_evaluation = evaluate_market(
				projection=float(projection),
				line=line,
				volatility=float(
					projection_volatility
					or market_volatility_floor(sport_label, raw_market)
				),
				sport=sport_label,
				market=raw_market,
				side=evaluation_side,
				sample_size=max(1, projection_sample_size),
				model_calibrated=projection_calibrated,
				empirical_hit_rate=(
					historical_hit_rate / 100
					if historical_hit_rate is not None
					else None
				),
				sharp_probability=selected_market_probability,
				decimal_odds=selected_decimal_odds,
				calibration_adjustment=calibration_adjustment,
			)
			hit_probability = market_evaluation.fair_probability

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
		data_age_seconds, data_stale = data_freshness(updated_at)
		market_rows = market_groups.get((
			str(row["sport"]).strip().lower(),
			str(row["game_id"] or ""),
			player.strip().lower(),
			raw_market.strip().lower(),
		), [])
		snapshot = market_snapshot(market_rows, line)
		market_origin_line = float(snapshot["origin_line"])
		book_count = int(snapshot["book_count"])
		best_over = snapshot["best_over"]
		best_under = snapshot["best_under"]
		public_bet_percentage = _row_optional_value(row, "public_bet_percentage")
		money_percentage = _row_optional_value(row, "money_percentage")
		volume_source = str(_row_optional_value(row, "volume_source") or "")
		if data_stale:
			recommendation.update(
				{
					"recommendedSide": "N/A",
					"pickText": "No Pick",
					"recommendationAvailable": False,
					"recommendationUnavailableReason": "stale_source_data",
					"edge": 0.0,
				}
			)
			recommended_pick = "N/A"
			adjusted_confidence = 0
			adjusted_tier = "No Pick"
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
					identity_confidence
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
				projectionSource=projection_source,
				projectionModelVersion=projection_model_version,
				projectionSampleSize=projection_sample_size,
				projectionVolatility=projection_volatility,
				projectionCalibrated=projection_calibrated,
				projectionLabel=projection_label,
				historicalHitRate=historical_hit_rate,
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
				recommendationAvailable=bool(
					recommendation["recommendationAvailable"]
				),
				recommendationUnavailableReason=str(
					recommendation["recommendationUnavailableReason"]
				),
				recommendationExplanation=str(
					recommendation.get("explanation") or ""
				),
				dataQualityScore=float(
					recommendation.get("dataQualityScore") or 0
				),
				dataQualityReasons=list(
					recommendation.get("dataQualityReasons") or []
				),
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
				dataAgeSeconds=data_age_seconds,
				dataStale=data_stale,
				sourceProvider=(
					"sportsgameodds"
					if str(row["game_id"]).startswith("sgo:")
					else "odds-api"
				),
				injuryStatus=injury_status,
				lineupStatus=lineup_status,
				imagePath=resolve_player_image(player, sport_label),
				overOdds=over_odds,
				underOdds=under_odds,
				marketOriginLine=float(market_origin_line),
				lineDiscrepancy=round(line - float(market_origin_line), 3),
				marketBookCount=book_count,
				bestOverOdds=best_over[0],
				bestUnderOdds=best_under[0],
				bestOverBook=best_over[1],
				bestUnderBook=best_under[1],
				publicBetPercentage=(
					float(public_bet_percentage)
					if isinstance(public_bet_percentage, (int, float))
					else None
				),
				moneyPercentage=(
					float(money_percentage)
					if isinstance(money_percentage, (int, float))
					else None
				),
				volumeSource=volume_source,
				overDecimalOdds=_american_to_decimal(over_odds),
				underDecimalOdds=_american_to_decimal(under_odds),
				overImpliedProbability=over_implied,
				underImpliedProbability=under_implied,
				noVigOverProbability=no_vig_over,
				noVigUnderProbability=no_vig_under,
				fairProbability=hit_probability,
				modelProbability=(
					market_evaluation.model_probability
					if market_evaluation is not None
					else None
				),
				marketProbability=(
					market_evaluation.market_probability
					if market_evaluation is not None
					else None
				),
				pushProbability=(
					market_evaluation.push_probability
					if market_evaluation is not None
					else 0
				),
				lossProbability=(
					market_evaluation.loss_probability
					if market_evaluation is not None
					else None
				),
				evPercentage=(
					market_evaluation.ev_percentage
					if market_evaluation is not None
					else None
				),
				fairDecimalOdds=(
					market_evaluation.fair_decimal_odds
					if market_evaluation is not None
					else None
				),
				isPositiveEv=bool(
					market_evaluation is not None
					and market_evaluation.is_positive_ev
					and recommendation["recommendationAvailable"]
					and adjusted_tier != "Pass"
				),
				probabilityMethod=(
					market_evaluation.distribution
					if market_evaluation is not None
					else ""
				),
				probabilityMarketWeight=(
					market_evaluation.market_weight
					if market_evaluation is not None
					else 0
				),
				probabilityUncertainty=(
					market_evaluation.uncertainty
					if market_evaluation is not None
					else None
				),
				probabilityCalibrationAdjustment=(
					market_evaluation.calibration_adjustment
					if market_evaluation is not None
					else 0
				),
				probabilityCalibrationSampleSize=calibration_sample_size,
				recommendedStakeFraction=(
					market_evaluation.recommended_stake_fraction
					if market_evaluation is not None
					else 0
				),
			)
		)

	deduped: dict[tuple[str, str, str, str, float, str], PropResponse] = {}
	for prop in results:
		key = (
			prop.sport.strip().lower(),
			re.sub(r"[^a-z0-9]+", "", prop.matchup.lower()),
			re.sub(r"[^a-z0-9]+", "", prop.player.lower()),
			prop.marketKey.strip().lower(),
			float(prop.line),
			prop.sportsbook.strip().lower(),
		)
		existing = deduped.get(key)
		if existing is None or prop.sourceProvider == "sportsgameodds":
			deduped[key] = prop
	results = list(deduped.values())
	enrich_props(results)
	return results
