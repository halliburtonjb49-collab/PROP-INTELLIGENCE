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
import logging

logger = logging.getLogger(__name__)

from services.prop_verification_service import (
	display_matchup,
	display_team_name,
	verify_prop,
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
from services.prop_probability_service import choose_over_under, evaluate_market, shin_method_devig
from services.market_calibration_service import market_calibration_adjustment
from services.prop_intelligence_service import analyze_prop
from services.prop_trust_service import build_prop_trust, build_research_capsule

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


def _safe_float(value: object, default: float | None = None) -> float | None:
	try:
		if value is None:
			return default
		return float(value)
	except (TypeError, ValueError):
		return default


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


def apply_prop_intelligence_recommendation(
	recommendation: dict[str, object],
	*,
	projection: object,
	line: object,
	projected_volatility: object,
	over_odds: object,
	under_odds: object,
	sport: str,
	market: str,
	bankroll: float = 1000.0,
	kelly_fraction: float = 0.25,
	simulations: int = 2000,
	seed: int = 42,
	pitcher_k_pct: float | None = None,
	lineup_k_pct: float | None = None,
	pitches_per_start: float | None = None,
	pitches_per_batter: float | None = None,
	pitcher_csw: float | None = None,
	lineup_csw_against: float | None = None,
	temp_f: float = 70.0,
	umpire_k_boost: float = 0.0,
	park_k_factor: float = 1.0,
) -> dict[str, object]:
	def _decimalize(odds: object) -> float | None:
		if not isinstance(odds, (int, float)):
			return None
		value = float(odds)
		if value <= 0:
			return None
		if value >= 20 or value <= -20:
			return _american_to_decimal(value)
		return value

	decimal_over_odds = _decimalize(over_odds)
	decimal_under_odds = _decimalize(under_odds)
	analysis = analyze_prop(
		player="",
		sport=sport,
		market=market,
		line=line,
		projected_mean=projection,
		projected_std_dev=projected_volatility,
		sharp_over_odds=decimal_over_odds,
		sharp_under_odds=decimal_under_odds,
		retail_over_odds=decimal_over_odds,
		retail_under_odds=decimal_under_odds,
		bankroll=bankroll,
		kelly_fraction=kelly_fraction,
		simulations=simulations,
		seed=seed,
		pitcher_k_pct=pitcher_k_pct,
		lineup_k_pct=lineup_k_pct,
		pitches_per_start=pitches_per_start,
		pitches_per_batter=pitches_per_batter,
		pitcher_csw=pitcher_csw,
		lineup_csw_against=lineup_csw_against,
		temp_f=temp_f,
		umpire_k_boost=umpire_k_boost,
		park_k_factor=park_k_factor,
	)
	if analysis["recommendation"] == "PASS":
		return {
			**recommendation,
			"recommendedSide": "N/A",
			"pickText": "No Pick",
			"recommendationAvailable": False,
			"recommendationUnavailableReason": "prop_intelligence_pass",
			"recommendationEdge": 0.0,
			"confidence": 0,
			"tier": "No Pick",
		}

	confidence = max(50, min(99, int(analysis["confidence"])))
	return {
		**recommendation,
		"recommendedSide": analysis["recommendation"],
		"pickText": analysis["recommendation"].title(),
		"recommendationAvailable": True,
		"recommendationUnavailableReason": "",
		"recommendationEdge": float(analysis.get("edgePercent", 0.0) or 0.0),
		"confidence": confidence,
		"tier": _tier_from_confidence(confidence, analysis["recommendation"]),
		"analysisMethod": str(analysis.get("method") or ""),
		"skillSource": str(analysis.get("skillSource") or ""),
		"projectedBattersFaced": analysis.get("projectedBattersFaced"),
		"usedFallbackPitcherRate": bool(analysis.get("usedFallbackPitcherRate")),
		"usedFallbackLineupRate": bool(analysis.get("usedFallbackLineupRate")),
		"usedFallbackTbf": bool(analysis.get("usedFallbackTbf")),
		"usedMarketBlend": bool(analysis.get("usedMarketBlend")),
		"recommendationExplanation": (
			f"Prop-intelligence model estimated a {analysis['recommendation'].lower()} edge with "
			f"{analysis['expectedValuePercent']:.2f}% EV."
		),
	}


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
		# Feeds hand back team identifiers when they have no display name,
		# so CLEVELAND_GUARDIANS_MLB reaches the card verbatim unless it is
		# turned into something a person would write.
		home_team = display_team_name(row["home_team"]) or str(row["home_team"] or "")
		away_team = display_team_name(row["away_team"]) or str(row["away_team"] or "")
		matchup = display_matchup(
			f"{away_team} @ {home_team}", home=home_team, away=away_team
		)
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
		projection_uses_minutes = False
		projected_minutes = None
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
				projection_uses_minutes = baseline.decomposed
				projected_minutes = baseline.projected_minutes
				projection_label = (
					"Minutes and per-minute rate model"
					if baseline.decomposed
					else "Baseline historical model"
				)
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
		over_odds = row["over_odds"]
		under_odds = row["under_odds"]
		pitcher_k_pct = _safe_float(_row_optional_value(row, "pitcher_k_pct"))
		lineup_k_pct = _safe_float(_row_optional_value(row, "lineup_k_pct"))
		pitches_per_start = _safe_float(_row_optional_value(row, "pitches_per_start"))
		pitches_per_batter = _safe_float(_row_optional_value(row, "pitches_per_batter"))
		pitcher_csw = _safe_float(_row_optional_value(row, "pitcher_csw"))
		lineup_csw_against = _safe_float(_row_optional_value(row, "lineup_csw_against"))
		temp_f = _safe_float(_row_optional_value(row, "temperature_f"), 70.0) or 70.0
		umpire_k_boost = _safe_float(_row_optional_value(row, "umpire_k_boost"), 0.0) or 0.0
		park_k_factor = _safe_float(_row_optional_value(row, "park_k_factor"), 1.0) or 1.0
		recommendation = apply_prop_intelligence_recommendation(
			recommendation,
			projection=projection,
			line=line,
			projected_volatility=(
				projection_volatility
				or market_volatility_floor(sport_label, raw_market)
			),
			over_odds=over_odds,
			under_odds=under_odds,
			sport=sport_label,
			market=raw_market,
			pitcher_k_pct=pitcher_k_pct,
			lineup_k_pct=lineup_k_pct,
			pitches_per_start=pitches_per_start,
			pitches_per_batter=pitches_per_batter,
			pitcher_csw=pitcher_csw,
			lineup_csw_against=lineup_csw_against,
			temp_f=temp_f,
			umpire_k_boost=umpire_k_boost,
			park_k_factor=park_k_factor,
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
		calibration_adjustment = 0.0
		calibration_sample_size = 0
		selection_reason = str(
			recommendation.get("recommendationUnavailableReason") or ""
		)
		selection_adjusted_probability = None
		model_signal_allowed = bool(recommendation.get("recommendationAvailable"))
		if projection is not None:
			evaluations = {}
			calibrations = {}
			for side in ("OVER", "UNDER"):
				adjustment, adjustment_sample = market_calibration_adjustment(
					sport_label,
					raw_market,
					projection_model_version,
					side,
				)
				calibrations[side] = (adjustment, adjustment_sample)
				market_probability = no_vig_over if side == "OVER" else no_vig_under
				decimal_odds = _american_to_decimal(
					over_odds if side == "OVER" else under_odds
				)
				empirical = None
				if historical_hit_rate is not None:
					projection_side = "OVER" if float(projection) > line else "UNDER"
					empirical = historical_hit_rate / 100
					if side != projection_side:
						empirical = 1 - empirical
				evaluations[side] = evaluate_market(
					projection=float(projection),
					line=line,
					volatility=float(
						projection_volatility
						or market_volatility_floor(sport_label, raw_market)
					),
					sport=sport_label,
					market=raw_market,
					side=side,
					sample_size=max(1, projection_sample_size),
					model_calibrated=projection_calibrated,
					empirical_hit_rate=empirical,
					sharp_probability=market_probability,
					decimal_odds=decimal_odds,
					calibration_adjustment=adjustment,
				)
			decision = choose_over_under(evaluations["OVER"], evaluations["UNDER"])
			selection_reason = decision.reason
			selection_adjusted_probability = decision.uncertainty_adjusted_probability
			if model_signal_allowed and decision.side in {"OVER", "UNDER"}:
				recommended_pick = decision.side
				recommended_side = decision.side
				market_evaluation = evaluations[decision.side]
				calibration_adjustment, calibration_sample_size = calibrations[decision.side]
				hit_probability = market_evaluation.fair_probability
				adjusted_confidence = adjust_confidence_for_availability(
					base_confidence=decision.confidence,
					injury_status=injury_status,
					lineup_status=lineup_status,
				)
				adjusted_tier = _tier_from_confidence(adjusted_confidence, decision.side)
				recommendation.update({
					"recommendedSide": decision.side,
					"pickText": decision.side.title(),
					"confidence": adjusted_confidence,
					"tier": adjusted_tier,
					"recommendationAvailable": True,
					"recommendationUnavailableReason": "",
				})
			else:
				recommended_pick = "N/A"
				recommended_side = "N/A"
				adjusted_confidence = 0
				adjusted_tier = "No Pick"
				recommendation.update({
					"recommendedSide": "N/A",
					"pickText": "No Pick",
					"confidence": 0,
					"tier": "No Pick",
					"recommendationAvailable": False,
					"recommendationUnavailableReason": selection_reason,
				})

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
				projectionUsesMinutes=projection_uses_minutes,
				projectedMinutes=projected_minutes,
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
				recommendationExplainability=(
					dict(recommendation.get("explainability") or {})
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
				selectionMethod="calibrated-ensemble-v1",
				selectionReason=selection_reason,
				uncertaintyAdjustedProbability=selection_adjusted_probability,
				recommendedStakeFraction=(
					market_evaluation.recommended_stake_fraction
					if market_evaluation is not None
					else 0
				),
				pitcherKPercent=pitcher_k_pct,
				lineupKPercent=lineup_k_pct,
				pitchesPerStart=pitches_per_start,
				pitchesPerBatter=pitches_per_batter,
				pitcherCsw=pitcher_csw,
				lineupCswAgainst=lineup_csw_against,
				temperatureF=temp_f,
				umpireKBoost=umpire_k_boost,
				parkKFactor=park_k_factor,
				strikeoutModelMethod=str(recommendation.get("analysisMethod") or ""),
				strikeoutSkillSource=str(recommendation.get("skillSource") or ""),
				strikeoutProjectedBattersFaced=(
					int(recommendation["projectedBattersFaced"])
					if recommendation.get("projectedBattersFaced") is not None
					else None
				),
				strikeoutUsedFallbackPitcherRate=bool(recommendation.get("usedFallbackPitcherRate")),
				strikeoutUsedFallbackLineupRate=bool(recommendation.get("usedFallbackLineupRate")),
				strikeoutUsedFallbackTbf=bool(recommendation.get("usedFallbackTbf")),
				strikeoutUsedMarketBlend=bool(recommendation.get("usedMarketBlend")),
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
	return _verified_props(results)


def _verified_props(props: list[PropResponse]) -> list[PropResponse]:
	"""Mark every prop, and withhold the ones that make no sense.

	A prop naming a market its sport does not have, or a source it cannot
	identify, is not a card with a gap in it -- it is the feed saying it
	does not know what this is. Those are dropped. A prop that is merely
	incomplete stays visible but cannot be selected, because a pick built
	on an unverified prop is a pick built on nothing.
	"""

	shown: list[PropResponse] = []
	quarantined = 0
	for prop in props:
		result = verify_prop(prop)
		prop.verificationStatus = result.status
		prop.verificationReasons = list(result.reasons)
		prop.selectable = result.selectable
		if not result.selectable and not prop.recommendationUnavailableReason:
			prop.recommendationUnavailableReason = result.reasons[0]
		if not result.selectable:
			prop.recommendationAvailable = False
		trust = build_prop_trust(prop)
		prop.piTrustScore = int(trust['score'])
		prop.piTrustBand = str(trust['band'])
		prop.piTrustResearchReady = bool(trust['researchReady'])
		prop.piTrustFactors = list(trust['factors'])
		prop.piTrustWarnings = list(trust['warnings'])
		prop.researchCapsule = build_research_capsule(prop, trust)
		if result.displayable:
			shown.append(prop)
		else:
			quarantined += 1
	if quarantined:
		logger.info(
			"withheld %s of %s props that failed verification",
			quarantined,
			len(props),
		)
	return shown
