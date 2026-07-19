import asyncio
import hashlib
import logging
import os
import time
from contextlib import asynccontextmanager, suppress
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone, tzinfo
from collections import Counter, defaultdict
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import BackgroundTasks, Body, Depends, FastAPI, Header, HTTPException, Query, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
import requests
from threading import Lock

from config import CORS_ALLOWED_ORIGINS, HTTP_TIMEOUT_SECONDS, LIVE_ODDS_SYNC_MIN_SECONDS, WNBA_LEAGUE_ID
from database.postgres import (
	check_database_connection,
	close_database_pool,
	database_is_configured,
)
from models.prop_builder import (
	PropBuilderRequest,
	PropBuilderResponse,
	PropReplacementRequest,
)
from models.prop import PropResponse
from models.prop_line_movement import (
	PropLineMovementRequest,
	PropLineMovementResponse,
)
from models.prop_builder_history import (
	PropBuilderHistory,
	PropBuilderHistoryCreate,
)
from models.prop_builder_performance import (
	PropBuilderPerformanceResponse,
)
from models.prop_builder_preset import (
	PropBuilderPreset,
	PropBuilderPresetCreate,
)
from models.prop_builder_strategy import (
	PropBuilderStrategyResponse,
)
from models.slip import LegResultUpdate, SlipClosingLinesUpdate, SlipCreate, SlipPreview
from providers.api_sports_basketball import (
	ApiSportsBasketballProvider,
)
from providers.api_sports_baseball import ApiSportsBaseballProvider
from providers.mock_player_stats import MockPlayerStatsProvider
from services.automatic_grader import grade_event_slips
from services.game_status_service import (
	refresh_saved_slip_game_statuses,
)
from services.prop_service import get_props
from services.prop_builder_service import (
	build_prop_slip,
	replace_prop_leg,
)
from services.prop_line_movement_service import (
	check_prop_line_movement,
)
from services.prop_builder_preset_service import (
	create_prop_builder_preset,
	delete_prop_builder_preset,
	list_prop_builder_presets,
	seed_default_prop_builder_presets,
)
from services.prop_builder_history_service import (
	clear_prop_builder_history,
	create_prop_builder_history,
	delete_prop_builder_history,
	get_prop_builder_history,
	initialize_prop_builder_history,
	list_prop_builder_history,
)
from services.prop_builder_history_grader import (
	grade_prop_builder_history,
)
from services.prop_builder_performance_service import (
	get_prop_builder_performance,
)
from services.prop_builder_strategy_service import (
	get_prop_builder_strategy,
)
from services.score_service import fetch_scores
from services.odds_service import fetch_events, quota_snapshot
from services.slip_service import (
	capture_closing_lines_from_props,
	slip_storage_health,
	calculate_payout_preview,
	create_slip,
	get_slips,
	update_slip_game_statuses,
	update_slip_closing_lines,
	update_slip_results,
	update_slip_status,
)
from services.live_stats_service import get_live_player_stat
from services.sync_service import run_global_sync_pipeline
from services.prop_recommendation_service import (
	build_prop_recommendation,
)
from services.time_utils import (
	format_display_time,
	parse_to_utc_iso,
)
from services.market_normalizer import normalize_market
from services.team_normalizer import normalize_team_name
from services.player_identity_service import (
	bootstrap_identity_candidates,
	load_identity_map,
	save_identity_map,
	unresolved_identity_rows,
	upsert_identity_entry,
)
from services.player_availability_service import (
	load_status_map,
	save_status_map,
	upsert_player_availability,
)
from services.wnba_grading_service import (
	diagnose_wnba_game,
	grade_active_wnba_slips,
)
from services.wnba_mapping_service import map_wnba_event
from services.api_auth_service import require_admin, require_user_id
from routers.intelligence import router as intelligence_router
from routers.billing import router as billing_router
from routers.realtime import hub as realtime_hub, router as realtime_router
from routers.operations import router as operations_router

logging.basicConfig(
	level=logging.INFO,
	format=(
		"%(asctime)s | %(levelname)s | "
		"%(name)s | %(message)s"
	),
)


@asynccontextmanager
async def lifespan(_: FastAPI):
	seed_default_prop_builder_presets()
	initialize_prop_builder_history()
	storage = slip_storage_health()
	if storage["status"] != "ok":
		raise RuntimeError(
			"Ticket storage is unavailable: "
			f"{storage.get('error', 'unknown error')}"
		)
	logging.info(
		"Ticket storage ready mode=%s path=%s",
		storage["mode"],
		storage["path"],
	)
	startup_sync_task = asyncio.create_task(_ensure_props_available())
	try:
		yield
	finally:
		startup_sync_task.cancel()
		with suppress(asyncio.CancelledError):
			await startup_sync_task
		close_database_pool()

app = FastAPI(
	title="PROP INTELLIGENCE API",
	version="1.2.0",
	lifespan=lifespan,
)

APP_VERSION = os.getenv("RENDER_GIT_COMMIT", os.getenv("APP_VERSION", "development"))
_prop_catalog_lock = Lock()
_prop_catalog: dict[str, object] = {"loadedAt": 0.0, "props": []}
_prop_metrics_lock = Lock()
_prop_metrics: dict[str, object] = {
	"requests": 0,
	"errors": 0,
	"emptyResponses": 0,
	"lastDurationMs": 0,
	"lastPayloadBytes": 0,
	"lastServedAt": None,
}

app.include_router(intelligence_router)
app.include_router(billing_router)
app.include_router(realtime_router)
app.include_router(operations_router)

app.add_middleware(
	CORSMiddleware,
	allow_origins=CORS_ALLOWED_ORIGINS,
	allow_origin_regex=r"https://([a-z0-9-]+\.)?propsintell\.com",
	allow_credentials=False,
	allow_methods=["*"],
	allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1000, compresslevel=5)


def _cached_prop_catalog() -> list[PropResponse]:
	now = time.monotonic()
	with _prop_catalog_lock:
		loaded_at = float(_prop_catalog["loadedAt"] or 0.0)
		cached = _prop_catalog["props"]
		if isinstance(cached, list) and cached and now - loaded_at < 20:
			return cached
	props = get_props()
	with _prop_catalog_lock:
		_prop_catalog.update(loadedAt=now, props=props)
	return props


def _invalidate_prop_catalog() -> None:
	with _prop_catalog_lock:
		_prop_catalog.update(loadedAt=0.0, props=[])

_sync_run_lock = Lock()
_sync_state_lock = Lock()
_sync_state: dict[str, object] = {
	"status": "idle",
	"startedAt": None,
	"finishedAt": None,
	"results": [],
	"error": None,
	"cooldownSeconds": LIVE_ODDS_SYNC_MIN_SECONDS,
	"nextAllowedAt": None,
}


def _sync_state_snapshot() -> dict[str, object]:
	with _sync_state_lock:
		return dict(_sync_state)


def _sync_is_fresh(now: datetime | None = None) -> bool:
	current = now or datetime.now(timezone.utc)
	with _sync_state_lock:
		finished_raw = _sync_state.get("finishedAt")
	if not finished_raw:
		return False
	try:
		finished = datetime.fromisoformat(str(finished_raw).replace("Z", "+00:00"))
	except ValueError:
		return False
	if finished.tzinfo is None:
		finished = finished.replace(tzinfo=timezone.utc)
	return (current - finished).total_seconds() < _effective_sync_cooldown_seconds()


def _effective_sync_cooldown_seconds() -> int:
	quota = quota_snapshot()
	remaining = quota.get("remaining")
	if isinstance(remaining, int):
		if remaining <= 10:
			return max(LIVE_ODDS_SYNC_MIN_SECONDS, 3600)
		if quota.get("lowQuota") is True:
			return max(LIVE_ODDS_SYNC_MIN_SECONDS, 1800)
	return LIVE_ODDS_SYNC_MIN_SECONDS


def _mark_sync_running() -> None:
	with _sync_state_lock:
		_sync_state.update(
			status="running", startedAt=datetime.now(timezone.utc).isoformat(),
			finishedAt=None, results=[], error=None, nextAllowedAt=None,
			fastLaneCompletedAt=None, fastLaneResults=[],
		)


def _run_sync_background() -> None:
	try:
		def mark_fast_lane_complete(results: list[dict[str, object]]) -> None:
			_invalidate_prop_catalog()
			with _sync_state_lock:
				_sync_state.update(
					fastLaneCompletedAt=datetime.now(timezone.utc).isoformat(),
					fastLaneResults=results,
				)

		results = run_global_sync_pipeline(mark_fast_lane_complete)
		_invalidate_prop_catalog()
		clv_capture = capture_closing_lines_from_props(get_props())
		quota = quota_snapshot()
		with _sync_state_lock:
			finished = datetime.now(timezone.utc)
			cooldown = _effective_sync_cooldown_seconds()
			_sync_state.update(
				status="complete",
				finishedAt=finished.isoformat(),
				cooldownSeconds=cooldown,
				nextAllowedAt=(finished + timedelta(seconds=cooldown)).isoformat(),
				results=results,
				clvCapture=clv_capture,
				providerQuota=quota,
				error=None,
			)
	except Exception as exc:
		logging.exception("Background prop sync failed")
		with _sync_state_lock:
			_sync_state.update(
				status="failed",
				finishedAt=datetime.now(timezone.utc).isoformat(),
				error=str(exc),
			)
	finally:
		_sync_run_lock.release()


async def _ensure_props_available() -> None:
	"""Populate an empty production cache without waiting for the cron schedule."""
	attempts = max(1, int(os.getenv("EMPTY_PROP_SYNC_ATTEMPTS", "3")))
	retry_seconds = max(30, int(os.getenv("EMPTY_PROP_SYNC_RETRY_SECONDS", "300")))
	for attempt in range(1, attempts + 1):
		if get_props():
			logging.info("Startup prop check ready attempt=%s", attempt)
			return
		if _sync_run_lock.acquire(blocking=False):
			logging.warning("Prop cache empty; starting recovery sync attempt=%s/%s", attempt, attempts)
			_mark_sync_running()
			await asyncio.to_thread(_run_sync_background)
		else:
			logging.info("Prop recovery sync already running attempt=%s/%s", attempt, attempts)
		if get_props():
			logging.info("Prop recovery sync restored live feed attempt=%s", attempt)
			return
		if attempt < attempts:
			logging.warning("Prop feed still empty; retrying in %s seconds", retry_seconds)
			await asyncio.sleep(retry_seconds)
	logging.error("Prop feed remained empty after %s recovery attempts", attempts)


SCOREBOARD_SPORT_KEYS: list[tuple[str, str]] = [
	("NBA", "basketball_nba"),
	("WNBA", "basketball_wnba"),
	("MLB", "baseball_mlb"),
	("NFL", "americanfootball_nfl"),
	("NHL", "icehockey_nhl"),
	("EPL", "soccer_epl"),
	("MLS", "soccer_usa_mls"),
	("UFC", "mma_mixed_martial_arts"),
]

ESPN_SCOREBOARD_PATHS: dict[str, str] = {
	"NBA": "basketball/nba",
	"WNBA": "basketball/wnba",
	"MLB": "baseball/mlb",
	"NFL": "football/nfl",
	"NHL": "hockey/nhl",
}

VALID_BULK_MODES = {"merge", "replace"}


def _normalize_bulk_mode(mode: str) -> str:
	normalized = mode.strip().lower()
	if normalized not in VALID_BULK_MODES:
		raise HTTPException(
			status_code=400,
			detail=(
				"Invalid mode. Expected one of: "
				f"{', '.join(sorted(VALID_BULK_MODES))}."
			),
		)
	return normalized


def _http_validation_error(
	message: str,
	errors: list[str],
) -> HTTPException:
	return HTTPException(
		status_code=400,
		detail={
			"message": message,
			"errors": errors[:30],
		},
	)


def _validate_identity_bulk_body(
	body: dict[str, object],
) -> dict[str, dict[str, dict[str, object]]]:
	incoming_providers = body.get("providers")
	if not isinstance(incoming_providers, dict):
		raise HTTPException(
			status_code=400,
			detail="Body must include a providers object.",
		)

	errors: list[str] = []
	validated: dict[str, dict[str, dict[str, object]]] = {}

	for provider_name, provider_map in incoming_providers.items():
		provider_key = str(provider_name).strip().lower()
		if not provider_key:
			errors.append("Provider key cannot be empty.")
			continue
		if not isinstance(provider_map, dict):
			errors.append(f"providers.{provider_key} must be an object.")
			continue

		validated_provider: dict[str, dict[str, object]] = {}
		for source_player_id, entry in provider_map.items():
			source_id = str(source_player_id).strip()
			if not source_id:
				errors.append(
					f"providers.{provider_key} contains an empty source_player_id key."
				)
				continue
			if not isinstance(entry, dict):
				errors.append(
					f"providers.{provider_key}.{source_id} must be an object."
				)
				continue

			canonical = str(
				entry.get("canonical_player_id")
				or entry.get("canonical_player")
				or entry.get("player")
				or ""
			).strip()
			if not canonical:
				errors.append(
					f"providers.{provider_key}.{source_id} requires canonical_player_id."
				)
				continue

			aliases_raw = entry.get("aliases", [])
			if aliases_raw is None:
				aliases_raw = []
			if not isinstance(aliases_raw, list):
				errors.append(
					f"providers.{provider_key}.{source_id}.aliases must be a list."
				)
				continue

			validated_provider[source_id] = {
				"canonical_player_id": canonical,
				"full_name": str(
					entry.get("full_name")
					or entry.get("canonical_player")
					or entry.get("player")
					or ""
				).strip(),
				"aliases": [
					str(item).strip()
					for item in aliases_raw
					if str(item).strip()
				],
			}

		validated[provider_key] = validated_provider

	if errors:
		raise _http_validation_error(
			"Identity bulk payload validation failed.",
			errors,
		)

	return validated


def _validate_availability_bulk_body(
	body: dict[str, object],
) -> dict[str, dict[str, str]]:
	incoming_players = body.get("players")
	if not isinstance(incoming_players, dict):
		raise HTTPException(
			status_code=400,
			detail="Body must include a players object.",
		)

	errors: list[str] = []
	validated: dict[str, dict[str, str]] = {}

	for canonical_player_id, entry in incoming_players.items():
		canonical = str(canonical_player_id).strip()
		if not canonical:
			errors.append("players contains an empty canonical_player_id key.")
			continue
		if not isinstance(entry, dict):
			errors.append(f"players.{canonical} must be an object.")
			continue

		injury_status = str(entry.get("injury_status") or "unknown").strip().lower()
		lineup_status = str(entry.get("lineup_status") or "unknown").strip().lower()
		notes = str(entry.get("notes") or "").strip()

		validated[canonical] = {
			"injury_status": injury_status,
			"lineup_status": lineup_status,
			"notes": notes,
		}

	if errors:
		raise _http_validation_error(
			"Availability bulk payload validation failed.",
			errors,
		)

	return validated


def _scoreboard_timezone() -> tzinfo:
	configured = os.getenv("PROP_INTELLIGENCE_TIMEZONE", "America/Chicago").strip()
	try:
		return ZoneInfo(configured)
	except ZoneInfoNotFoundError:
		return datetime.now().astimezone().tzinfo or timezone.utc


def _parse_start_time(value: object) -> datetime | None:
	if value is None:
		return None
	try:
		parsed = datetime.fromisoformat(
			str(value).replace("Z", "+00:00")
		)
		if parsed.tzinfo is None:
			return parsed.replace(tzinfo=timezone.utc)
		return parsed
	except ValueError:
		return None


def _local_event_date(value: object) -> date | None:
	start_time = _parse_start_time(value)
	if start_time is None:
		return None
	return start_time.astimezone(_scoreboard_timezone()).date()


def _extract_score(
	event: dict[str, object],
	team_name: str,
) -> int | None:
	raw_scores = event.get("scores")
	if not isinstance(raw_scores, list):
		return None

	for item in raw_scores:
		if not isinstance(item, dict):
			continue
		if str(item.get("name", "")).strip() != team_name:
			continue
		try:
			return int(str(item.get("score", "")).strip())
		except ValueError:
			return None

	return None


def _normalize_team_name_for_key(value: object) -> str:
	return str(value or "").strip().upper()


def _scoreboard_identity(
	away_team: object,
	home_team: object,
) -> str:
	return (
		f"{_normalize_team_name_for_key(away_team)}|"
		f"{_normalize_team_name_for_key(home_team)}"
	)


def _first_text_from_mapping(value: object, *keys: str) -> str:
	if not isinstance(value, dict):
		return ""
	for key in keys:
		text = str(value.get(key) or "").strip()
		if text:
			return text
	return ""


def _espn_scoreboard_games_for_sport(
	league: str,
	target_date: date,
) -> list[dict[str, object]]:
	path = ESPN_SCOREBOARD_PATHS.get(league)
	if path is None:
		return []

	try:
		response = requests.get(
			f"https://site.api.espn.com/apis/site/v2/sports/{path}/scoreboard",
			params={"dates": target_date.strftime("%Y%m%d")},
			timeout=HTTP_TIMEOUT_SECONDS,
		)
		response.raise_for_status()
		payload = response.json()
	except requests.RequestException:
		return []

	events = payload.get("events") if isinstance(payload, dict) else None
	if not isinstance(events, list):
		return []

	games: list[dict[str, object]] = []
	for event in events:
		if not isinstance(event, dict):
			continue
		competitions = event.get("competitions")
		if not isinstance(competitions, list) or not competitions:
			continue
		competition = competitions[0]
		if not isinstance(competition, dict):
			continue
		competitors = competition.get("competitors")
		if not isinstance(competitors, list) or len(competitors) < 2:
			continue

		away_competitor = None
		home_competitor = None
		for competitor in competitors:
			if not isinstance(competitor, dict):
				continue
			home_away = str(competitor.get("homeAway") or "").strip().lower()
			if home_away == "away":
				away_competitor = competitor
			elif home_away == "home":
				home_competitor = competitor

		if away_competitor is None or home_competitor is None:
			continue

		away_team_value = away_competitor.get("team")
		home_team_value = home_competitor.get("team")
		away_team = (
			str(away_team_value.get("displayName") or "")
			if isinstance(away_team_value, dict)
			else str(away_team_value or "")
		)
		home_team = (
			str(home_team_value.get("displayName") or "")
			if isinstance(home_team_value, dict)
			else str(home_team_value or "")
		)

		status = competition.get("status")
		status_type = status.get("type") if isinstance(status, dict) else None
		state = str(status_type.get("state") or "").strip().lower() if isinstance(status_type, dict) else ""
		detail = _first_text_from_mapping(
			status_type,
			"shortDetail",
			"detail",
		)
		if not detail and isinstance(status, dict):
			detail = str(status.get("displayClock") or "").strip()

		games.append(
			{
				"id": str(event.get("id") or ""),
				"identity": _scoreboard_identity(
					away_team,
					home_team,
				),
				"away_team": away_team,
				"home_team": home_team,
				"commence_time": str(event.get("date") or ""),
				"completed": state == "post",
				"scores": [
					{
						"name": away_team,
						"score": str(away_competitor.get("score") or ""),
					},
					{
						"name": home_team,
						"score": str(home_competitor.get("score") or ""),
					},
				],
				"status": "LIVE" if state == "in" else "FINAL" if state == "post" else "UPCOMING",
				"detail": detail,
			},
		)

	return games


def _format_live_detail(event: dict[str, object], league: str) -> str:
	def _first_text(*keys: str) -> str:
		for key in keys:
			value = str(event.get(key) or "").strip()
			if value:
				return value
		return ""

	def _first_int(*keys: str) -> int | None:
		for key in keys:
			value = event.get(key)
			if value in (None, ""):
				continue
			try:
				return int(float(str(value).strip()))
			except (TypeError, ValueError):
				continue
		return None

	if league == "UFC":
		round_number = _first_int(
			"round",
			"Round",
			"result_round",
			"ResultRound",
		)
		fight_time = _first_text(
			"time",
			"Time",
			"result_time",
			"ResultTime",
			"clock",
			"Clock",
		)
		parts: list[str] = []
		if round_number is not None:
			parts.append(f"ROUND {round_number}")
		if fight_time:
			parts.append(fight_time)
		return " • ".join(parts) if parts else "LIVE"

	clock = _first_text(
		"clock",
		"Clock",
		"time_remaining",
		"TimeRemaining",
		"time",
	)
	period = _first_int(
		"period",
		"Period",
		"quarter",
		"Quarter",
		"half",
		"Half",
		"inning",
		"Inning",
	)
	inning_half = _first_text(
		"inning_half",
		"InningHalf",
		"inningHalf",
		"half_inning",
		"HalfInning",
	).upper()

	if league in {"NBA", "WNBA", "NFL", "NHL"}:
		if period is not None and clock:
			return f"Q{period} {clock}"
		if period is not None:
			return f"Q{period}"
		if clock:
			return clock

	if league in {"EPL", "MLS"}:
		if period is not None and clock:
			return f"{period}H {clock}"
		if period is not None:
			return f"{period}H"
		if clock:
			return clock

	if league == "MLB":
		if inning_half and period is not None:
			prefix = "TOP" if inning_half.startswith("TOP") else "BOT" if inning_half.startswith("BOT") else inning_half
			if clock:
				return f"{prefix} {period} • {clock}"
			return f"{prefix} {period}"
		if period is not None and clock:
			return f"INNING {period} • {clock}"
		if period is not None:
			return f"INNING {period}"
		if clock:
			return clock

	if period is not None and clock:
		return f"P{period} {clock}"
	if period is not None:
		return f"P{period}"
	if clock:
		return clock

	return "LIVE"


def _normalize_scoreboard_game(
	event: dict[str, object],
	league: str,
	now: datetime,
	live_detail_map: dict[str, str] | None = None,
	shared_time_map: dict[str, dict[str, str]] | None = None,
) -> dict[str, object]:
	event_id = str(event.get("id") or "").strip()
	home_team = str(event.get("home_team") or "")
	away_team = str(event.get("away_team") or "")
	mapped = (
		(shared_time_map or {}).get(event_id)
		if event_id
		else None
	)
	start_time_utc = (
		mapped.get("startTimeUtc", "")
		if mapped is not None
		else parse_to_utc_iso(event.get("commence_time"))
	)
	display_time = (
		mapped.get("displayTime", "")
		if mapped is not None
		else format_display_time(start_time_utc)
	)
	start_time = _parse_start_time(start_time_utc)
	completed = bool(event.get("completed"))

	if completed:
		status = "FINAL"
	elif start_time is not None and start_time <= now:
		status = "LIVE"
	else:
		status = "UPCOMING"

	return {
		"id": (
			event_id
			or f"{league}-{away_team}-{home_team}"
		),
		"gameId": (
			event_id
			or f"{league}-{away_team}-{home_team}"
		),
		"sport": league,
		"league": league,
		"away_team": away_team,
		"home_team": home_team,
		"away_score": _extract_score(event, away_team),
		"home_score": _extract_score(event, home_team),
		"status": status,
		"detail": (
			(live_detail_map or {}).get(
				_scoreboard_identity(away_team, home_team)
			)
			or (_format_live_detail(event, league) if status == "LIVE" else "")
		),
		"startTimeUtc": start_time_utc,
		"displayTime": display_time,
		"start_time": (
			start_time.isoformat()
			if start_time is not None
			else None
		),
	}


def _shared_game_time_map() -> dict[str, dict[str, str]]:
	prop_list = get_props()
	shared: dict[str, dict[str, str]] = {}
	for prop in prop_list:
		row = prop.model_dump()
		event_id = str(
			row.get("eventId")
			or row.get("gameId")
			or ""
		).strip()
		if not event_id:
			continue
		start_time_utc = str(
			row.get("startTimeUtc")
			or row.get("gameStartTime")
			or ""
		).strip()
		display_time = str(
			row.get("displayTime")
			or row.get("gameTime")
			or ""
		).strip()
		if not start_time_utc and not display_time:
			continue
		shared[event_id] = {
			"startTimeUtc": start_time_utc,
			"displayTime": display_time,
		}
	return shared


def _event_identity(value: dict[str, object]) -> str:
	away_team = str(value.get("away_team") or "").strip().upper()
	home_team = str(value.get("home_team") or "").strip().upper()
	start_time = _parse_start_time(value.get("commence_time"))
	if away_team or home_team or start_time is not None:
		start_key = (
			start_time.replace(second=0, microsecond=0).isoformat()
			if start_time is not None
			else ""
		)
		return f"{away_team}|{home_team}|{start_key}"

	return str(value.get("id") or "").strip()


def _event_on_date(
	event: dict[str, object],
	*,
	target_date: date,
) -> bool:
	local_date = _local_event_date(event.get("commence_time"))
	return local_date == target_date


def _scoreboard_games_for_sport(
	*,
	league: str,
	sport_key: str,
	target_date: date,
	now: datetime,
	shared_time_map: dict[str, dict[str, str]] | None = None,
) -> list[dict[str, object]]:
	games: list[dict[str, object]] = []
	live_detail_map: dict[str, str] = {}
	espn_games = _espn_scoreboard_games_for_sport(
		league,
		target_date,
	)
	api_sports_baseball_games: list[dict[str, object]] = []
	if league == "MLB":
		try:
			api_sports_baseball_games = (
				ApiSportsBaseballProvider().get_games_by_date(target_date)
			)
		except Exception:
			logging.exception(
				"API-Sports baseball scoreboard fallback failed"
			)
	supplemental_games = [
		*espn_games,
		*api_sports_baseball_games,
	]
	if target_date == now.astimezone(_scoreboard_timezone()).date():
		for live_game in supplemental_games:
			if live_game.get("status") != "LIVE":
				continue
			identity = str(live_game.get("identity") or "").strip()
			if identity and str(live_game.get("detail") or "").strip():
				live_detail_map[identity] = str(live_game.get("detail") or "").strip()

	try:
		events = fetch_events(sport_key)
	except Exception:
		events = []

	try:
		scores = fetch_scores(sport_key, days_from=3)
	except Exception:
		scores = []

	score_by_id = {
		_event_identity(score): score
		for score in scores
		if isinstance(score, dict)
		and _event_identity(score)
		and _event_on_date(score, target_date=target_date)
	}

	seen_ids: set[str] = set()
	for raw_event in events:
		if not isinstance(raw_event, dict):
			continue
		if not _event_on_date(raw_event, target_date=target_date):
			continue

		event_id = _event_identity(raw_event)
		merged = dict(raw_event)
		if event_id in score_by_id:
			merged.update(score_by_id[event_id])
		seen_ids.add(event_id)
		games.append(
			_normalize_scoreboard_game(
				merged,
				league,
				now,
				live_detail_map=live_detail_map,
				shared_time_map=shared_time_map,
			)
		)

	for event_id, score_event in score_by_id.items():
		if event_id in seen_ids:
			continue
		games.append(
			_normalize_scoreboard_game(
				score_event,
				league,
				now,
				live_detail_map=live_detail_map,
				shared_time_map=shared_time_map,
			)
		)

	existing_matchups = {
		_scoreboard_identity(
			game.get("away_team"),
			game.get("home_team"),
		)
		for game in games
	}
	for supplemental_event in supplemental_games:
		identity = str(supplemental_event.get("identity") or "").strip()
		if not identity or identity in existing_matchups:
			continue
		if not _event_on_date(
			supplemental_event,
			target_date=target_date,
		):
			continue
		games.append(
			_normalize_scoreboard_game(
				supplemental_event,
				league,
				now,
				live_detail_map=live_detail_map,
				shared_time_map=shared_time_map,
			)
		)
		existing_matchups.add(identity)

	return games


def _scoreboard_preference(game: dict[str, object]) -> int:
	status = str(game.get("status") or "").upper()
	if status == "LIVE":
		return 3
	if status == "FINAL":
		return 2
	if status == "UPCOMING":
		return 1
	return 0


def _active_ticket_team(leg: object) -> str:
	if not isinstance(leg, dict):
		return ""
	team_value = leg.get("team") or leg.get("team_key") or ""
	return str(team_value).strip().upper()


def _grade_active_ticket_leg(
	*,
	side: str,
	current: float,
	line: float,
	game_status: str,
) -> str:
	if str(game_status).strip().lower() != "final":
		return "live"
	if current == line:
		return "push"
	normalized_side = str(side).strip().lower()
	if normalized_side == "over":
		return "win" if current > line else "loss"
	if normalized_side == "under":
		return "win" if current < line else "loss"
	return "live"


def _active_ticket_payload(*, season: str, user_id: str) -> dict[str, object]:
	active_slips = get_slips("active", user_id=user_id)
	if not active_slips:
		return {
			"slip_title": "Active Slip",
			"payout": "$0.00",
			"legs": [],
		}

	slip = active_slips[0]
	legs: list[dict[str, object]] = []
	for leg in slip.legs:
		game_status = "Final" if leg.game_completed else (
			"Live" if str(leg.game_status).strip().lower() == "live" else "Scheduled"
		)
		current_value = get_live_player_stat(
			player_name=leg.player,
			team="",
			prop_type=leg.market,
			sport=leg.sport,
			season=season,
		)
		result = _grade_active_ticket_leg(
			side=leg.side,
			current=current_value,
			line=leg.line,
			game_status=game_status,
		)
		legs.append(
			{
				"id": leg.prop_id,
				"prop_id": leg.prop_id,
				"sport": leg.sport,
				"game": leg.matchup,
				"matchup": leg.matchup,
				"player": leg.player,
				"team": "",
				"position": "",
				"prop_type": leg.market,
				"market": leg.market,
				"sportsbook": leg.sportsbook,
				"side": leg.side.lower(),
				"line": leg.line,
				"current": current_value,
				"result_value": current_value,
				"game_status": game_status,
				"player_image": "",
				"result": result,
				"result_status": result,
				"odds": leg.odds,
			}
		)

	return {
		"slip_id": slip.id,
		"slip_title": f"{len(slip.legs)}-Pick Active Ticket",
		"status": slip.status,
		"payout": f"${slip.potential_payout:.2f}",
		"created_at": slip.created_at,
		"legs": legs,
	}


@app.get("/health")
def health() -> dict[str, object]:
	storage = slip_storage_health()
	return {
		"status": "ok",
		"database": (
			"configured"
			if database_is_configured()
			else "not_configured"
		),
		"ticket_storage": str(storage["status"]),
		"ticket_storage_mode": str(storage.get("mode", "unknown")),
		"version": APP_VERSION,
		"propFeed": dict(_prop_metrics),
	}


@app.get("/api/operations/prop-feed-health")
def prop_feed_health() -> dict[str, object]:
	with _prop_metrics_lock:
		metrics = dict(_prop_metrics)
	requests_count = max(1, int(metrics["requests"]))
	return {
		"status": "ok" if int(metrics["errors"]) == 0 else "degraded",
		"version": APP_VERSION,
		"successRate": round(
			(requests_count - int(metrics["errors"])) / requests_count,
			4,
		),
		**metrics,
	}


@app.get("/health/storage")
def storage_health() -> dict[str, object]:
	storage = slip_storage_health()
	if storage["status"] != "ok":
		raise HTTPException(status_code=503, detail=storage)
	return storage


@app.get("/health/providers")
def provider_health() -> dict[str, object]:
	quota = quota_snapshot()
	return {
		"oddsApi": {
			"status": "low_quota" if quota["lowQuota"] else "ok",
			**quota,
		}
	}


@app.get("/health/database")
def database_health() -> dict[str, str]:
	if not database_is_configured():
		raise HTTPException(
			status_code=503,
			detail="DATABASE_URL is not configured.",
		)

	try:
		check_database_connection()
	except Exception as exc:
		logging.exception("PostgreSQL health check failed")
		raise HTTPException(
			status_code=503,
			detail="PostgreSQL is unavailable.",
		) from exc

	return {"status": "ok", "database": "connected"}


def _prop_alert_items() -> list[dict[str, object]]:
	prop_list = get_props()
	if not prop_list:
		return [
			{
				"sport": "ALL",
				"title": "No Props Loaded",
				"message": (
					"No props loaded yet. Alerts will appear "
					"as soon as data sync completes."
				),
				"edge": 0,
				"book": "All Books",
				"time": "now",
			}
		]

	rows = [prop.model_dump() for prop in prop_list]
	rows.sort(
		key=lambda row: int(row.get("edge") or 0),
		reverse=True,
	)
	best = rows[0]

	by_sport: dict[str, int] = {}
	for row in rows:
		sport = str(row.get("sport") or "ALL").strip().upper()
		if not sport:
			sport = "ALL"
		by_sport[sport] = by_sport.get(sport, 0) + 1

	top_sport = max(
		by_sport.items(),
		key=lambda item: item[1],
	)
	hot_count = sum(
		1
		for row in rows
		if int(row.get("edge") or 0) >= 90
	)

	alerts: list[dict[str, object]] = [
		{
			"sport": str(best.get("sport") or "ALL"),
			"title": "Best Edge Alert",
			"message": (
				f"{best.get('player', 'Unknown player')} "
				f"{int(best.get('edge') or 0)}% edge on "
				f"{best.get('market', 'market')}."
			),
			"edge": int(best.get("edge") or 0),
			"book": str(best.get("sportsbook") or "All Books"),
			"time": "now",
		},
		{
			"sport": top_sport[0],
			"title": "Most Active Sport",
			"message": (
				f"{top_sport[0]} has {top_sport[1]} props "
				"visible right now."
			),
			"edge": int(best.get("edge") or 0),
			"book": "All Books",
			"time": "now",
		},
	]

	if hot_count > 0:
		alerts.append(
			{
				"sport": "ALL",
				"title": "High Edge Cluster",
				"message": (
					f"{hot_count} props are at "
					"90%+ edge right now."
				),
				"edge": 90,
				"book": "All Books",
				"time": "now",
			}
		)

	return alerts


@app.get("/api/prop-alerts")
def prop_alerts() -> dict[str, object]:
	try:
		alerts = _prop_alert_items()
		return {
			"count": len(alerts),
			"alerts": alerts,
		}
	except Exception as exc:
		raise HTTPException(
			status_code=500,
			detail=f"Unable to load prop alerts: {exc}",
		) from exc


@app.get("/api/props")
def props(
	response: Response,
	side: str = Query(default="All"),
	tier: str = Query(default="All"),
	sportsbook: str = Query(default="All"),
	sport: str = Query(default="All"),
	category: str = Query(default="All"),
	search: str = Query(default=""),
	minConfidence: int = Query(default=0),
	sortBy: str = Query(default="confidence"),
	includePastDates: bool = Query(default=False),
	limit: int = Query(default=1500, ge=1, le=5000),
	offset: int = Query(default=0, ge=0),
	if_none_match: str | None = Header(default=None, alias="If-None-Match"),
) -> dict[str, object]:
	started_at = time.perf_counter()
	try:
		prop_list = _cached_prop_catalog()
		side_filter = side.strip().lower()
		tier_filter = tier.strip().lower()
		sportsbook_filter = sportsbook.strip().lower().replace(" ", "")
		sport_filter = sport.strip().lower().replace(" ", "")
		category_filter = category.strip().lower()
		search_filter = search.strip().lower()
		min_confidence = max(0, int(minConfidence))
		sort_by = sortBy.strip().lower()
		today_local = datetime.now(_scoreboard_timezone()).date()

		def _matches_filters(
			prop: PropResponse,
			*,
			apply_category: bool,
		) -> bool:
			row = prop.model_dump()
			start_time = _parse_start_time(row.get("startTimeUtc"))
			if not includePastDates:
				if start_time is None:
					return False
				event_date = start_time.astimezone(
					_scoreboard_timezone()
				).date()
				if event_date < today_local:
					return False
			recommended_side = str(
				row.get("recommendedSide") or ""
			).strip().lower()
			recommended_tier = str(
				row.get("tier") or ""
			).strip().lower()
			confidence = int(row.get("confidence") or 0)
			prop_sportsbook = str(row.get("sportsbook") or "").strip().lower().replace(" ", "")
			prop_sport = str(row.get("sport") or "").strip().lower().replace(" ", "")
			prop_category = str(row.get("category") or "").strip().lower()
			searchable = " ".join((
				str(row.get("player") or ""),
				str(row.get("matchup") or ""),
				str(row.get("market") or ""),
				str(row.get("category") or ""),
			)).lower()

			if side_filter != "all" and recommended_side != side_filter:
				return False
			if tier_filter != "all" and recommended_tier != tier_filter:
				return False
			if sportsbook_filter != "all" and prop_sportsbook != sportsbook_filter:
				return False
			if sport_filter != "all" and prop_sport != sport_filter:
				return False
			if (
				apply_category
				and category_filter != "all"
				and prop_category != category_filter
			):
				return False
			if search_filter and search_filter not in searchable:
				return False
			if confidence < min_confidence:
				return False
			return True

		facet_props = [
			prop for prop in prop_list
			if _matches_filters(prop, apply_category=False)
		]
		category_counts = Counter(
			str(prop.category or "other").strip().upper()
			for prop in facet_props
		)
		filtered_props = [
			prop for prop in facet_props
			if _matches_filters(prop, apply_category=True)
		]

		tier_rank = {
			"premium": 3,
			"strong": 2,
			"lean": 1,
			"pass": 0,
			"no pick": 0,
		}

		if sort_by == "edge":
			filtered_props.sort(
				key=lambda row: float(row.edge or 0),
				reverse=True,
			)
		elif sort_by == "premium":
			filtered_props.sort(
				key=lambda row: (
					tier_rank.get(
						str(row.tier or "no pick").strip().lower(),
						0,
					),
					int(row.confidence or 0),
				),
				reverse=True,
			)
		elif sort_by == "time":
			filtered_props.sort(
				key=lambda row: (
					_parse_start_time(row.startTimeUtc)
					or datetime.max.replace(tzinfo=timezone.utc)
				),
			)
		else:
			filtered_props.sort(
				key=lambda row: int(row.confidence or 0),
				reverse=True,
			)
			sort_by = "confidence"

		total_count = len(filtered_props)
		page = filtered_props[offset:offset + limit]
		payload = {
			"count": total_count,
			"facetCount": len(facet_props),
			"categoryCounts": dict(sorted(category_counts.items())),
			"returned": len(page),
			"offset": offset,
			"limit": limit,
			"hasMore": offset + len(page) < total_count,
			"props": [
				prop.model_dump()
				for prop in page
			],
			"filters": {
				"side": side,
				"tier": tier,
				"sportsbook": sportsbook,
				"sport": sport,
				"category": category,
				"search": search,
				"minConfidence": min_confidence,
				"sortBy": sort_by,
				"includePastDates": includePastDates,
			},
			"version": APP_VERSION,
		}
		etag_source = (
			f"{APP_VERSION}|{side}|{tier}|{sportsbook}|{sport}|{category}|"
			f"{search}|{min_confidence}|{sort_by}|{includePastDates}|"
			f"{limit}|{offset}|{total_count}|"
			f"{max((prop.lastUpdatedUtc for prop in page), default='')}"
		)
		etag = f'"{hashlib.sha256(etag_source.encode()).hexdigest()[:24]}"'
		response.headers["ETag"] = etag
		response.headers["Cache-Control"] = "public, max-age=15, stale-while-revalidate=120"
		response.headers["X-App-Version"] = APP_VERSION
		if if_none_match == etag:
			response.status_code = 304
			payload = {}
		duration_ms = int((time.perf_counter() - started_at) * 1000)
		payload_bytes = len(str(payload).encode("utf-8"))
		with _prop_metrics_lock:
			_prop_metrics.update(
				requests=int(_prop_metrics["requests"]) + 1,
				emptyResponses=int(_prop_metrics["emptyResponses"]) + (1 if total_count == 0 else 0),
				lastDurationMs=duration_ms,
				lastPayloadBytes=payload_bytes,
				lastServedAt=datetime.now(timezone.utc).isoformat(),
			)
		return payload
	except Exception as exc:
		with _prop_metrics_lock:
			_prop_metrics["requests"] = int(_prop_metrics["requests"]) + 1
			_prop_metrics["errors"] = int(_prop_metrics["errors"]) + 1
		raise HTTPException(
			status_code=500,
			detail=f"Unable to load props: {exc}",
		) from exc


@app.get("/api/props/ev")
def positive_ev_props(
	min_ev: float = Query(default=0.0),
	sport: str = Query(default="All"),
) -> dict[str, object]:
	"""Return only props backed by a genuine positive-EV calculation."""
	sport_filter = sport.strip().lower().replace(" ", "")
	minimum = float(min_ev)
	rows: list[dict[str, object]] = []
	for prop in _cached_prop_catalog():
		if sport_filter != "all" and prop.sport.strip().lower().replace(" ", "") != sport_filter:
			continue
		if prop.evPercentage is None or prop.fairProbability is None:
			continue
		if not prop.isPositiveEv or prop.evPercentage < minimum:
			continue
		rows.append(prop.model_dump())
	rows.sort(key=lambda item: float(item.get("evPercentage") or 0), reverse=True)
	return {
		"count": len(rows),
		"props": rows,
		"minEv": minimum,
		"sport": sport,
		"version": APP_VERSION,
	}


@app.get("/api/props-test")
def props_test() -> dict[str, object]:
	raw_props = [
		{
			"player": "Ernie Clement",
			"sport": "MLB",
			"market": "Total Bases",
			"line": 1.5,
			"projection": 2.1,
			"book": "PrizePicks",
			"imageUrl": "",
			"game_id": "mlb_tor_nyy",
			"displayTime": "7:05 PM",
			"matchup": "TOR @ NYY",
		},
		{
			"player": "Aaron Judge",
			"sport": "MLB",
			"market": "Strikeouts",
			"line": 1.5,
			"projection": 0.8,
			"book": "Underdog",
			"imageUrl": "",
			"game_id": "mlb_nyy_tor",
			"displayTime": "7:05 PM",
			"matchup": "NYY @ TOR",
		},
		{
			"player": "Stephen Curry",
			"sport": "NBA",
			"market": "Three-Pointers Made",
			"line": 4.5,
			"projection": 5.8,
			"book": "Sleeper",
			"imageUrl": "",
			"game_id": "nba_gsw_lal",
			"displayTime": "10:00 PM",
			"matchup": "GSW @ LAL",
		},
	]

	props_payload: list[dict[str, object]] = []
	for prop in raw_props:
		recommendation = build_prop_recommendation(
			projection=prop.get("projection"),
			line=prop.get("line"),
		)
		props_payload.append(
			{
				"player": prop.get("player"),
				"sport": prop.get("sport"),
				"market": prop.get("market"),
				"line": prop.get("line"),
				"projection": prop.get("projection"),
				"book": prop.get("book"),
				"imageUrl": prop.get("imageUrl"),
				"gameId": prop.get("game_id"),
				"displayTime": prop.get("displayTime"),
				"matchup": prop.get("matchup"),
				"recommendedSide": recommendation[
					"recommendedSide"
				],
				"confidence": recommendation[
					"confidence"
				],
				"edge": recommendation["edge"],
				"recommendationEdge": recommendation[
					"recommendationEdge"
				],
				"tier": recommendation["tier"],
				"pickText": recommendation["pickText"],
			}
		)

	return {"props": props_payload}


@app.post("/api/sync")
def sync_props(background_tasks: BackgroundTasks) -> dict[str, object]:
	if _sync_is_fresh():
		return {**_sync_state_snapshot(), "reusedFreshData": True,
			"message": "Current odds are still inside the server freshness window."}
	if not _sync_run_lock.acquire(blocking=False):
		return _sync_state_snapshot()
	if _sync_is_fresh():
		_sync_run_lock.release()
		return {**_sync_state_snapshot(), "reusedFreshData": True,
			"message": "Current odds are still inside the server freshness window."}
	_mark_sync_running()

	background_tasks.add_task(_run_sync_background)
	return {
		**_sync_state_snapshot(),
		"message": "Global sports sync started in the background.",
	}


@app.get("/api/sync/status")
def sync_status() -> dict[str, object]:
	return _sync_state_snapshot()


def _is_stale_timestamp(value: str, now_utc: datetime, max_minutes: int = 180) -> bool:
	if not value:
		return True
	try:
		parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
		if parsed.tzinfo is None:
			parsed = parsed.replace(tzinfo=timezone.utc)
		delta = now_utc - parsed.astimezone(timezone.utc)
		return delta.total_seconds() > (max_minutes * 60)
	except ValueError:
		return True


@app.get("/api/accuracy/audit")
def accuracy_audit() -> dict[str, object]:
	now_utc = datetime.now(timezone.utc)
	props = get_props()
	prop_rows = [item.model_dump() for item in props]

	issues: dict[str, list[str]] = {
		"game_schedule": [],
		"player_matching": [],
		"team_matching": [],
		"prop_category": [],
		"over_under": [],
		"odds_accuracy": [],
		"freshness": [],
	}

	status_counts: Counter[str] = Counter()
	doubleheader_count = 0
	neutral_site_count = 0
	canceled_count = 0
	delayed_count = 0
	missing_required_fields = 0
	timezone_parse_failures = 0
	past_date_rows = 0
	missing_player_ids = 0
	name_to_ids: dict[str, set[str]] = defaultdict(set)
	team_alias_groups: dict[str, set[str]] = defaultdict(set)
	unknown_categories = 0
	side_edge_mismatch = 0
	missing_over_under_prices = 0
	stale_rows = 0
	weak_identity_rows = 0
	unknown_availability_rows = 0

	for row in prop_rows:
		sport = str(row.get("sport") or "").strip()
		player = str(row.get("player") or "").strip()
		event_id = str(row.get("eventId") or row.get("gameId") or "").strip()
		market = str(row.get("market") or "").strip()
		market_key = str(row.get("marketKey") or "").strip()
		line = row.get("line")
		start_time_utc = str(row.get("startTimeUtc") or "").strip()
		game_status = str(row.get("gameStatus") or "").strip().lower()
		recommended_side = str(row.get("recommendedSide") or "").strip().lower()
		edge_signed = float(row.get("edgeSigned") or 0)
		over_odds = row.get("overOdds")
		under_odds = row.get("underOdds")
		last_updated = str(row.get("lastUpdatedUtc") or "").strip()
		player_id = str(row.get("playerId") or "").strip()
		identity_confidence = float(row.get("playerIdentityConfidence") or 0)
		injury_status = str(row.get("injuryStatus") or "unknown").strip().lower()
		lineup_status = str(row.get("lineupStatus") or "unknown").strip().lower()
		is_doubleheader = bool(row.get("isDoubleheader"))
		is_neutral = bool(row.get("isNeutralSite"))
		is_canceled = bool(row.get("isCanceled"))
		is_delayed = bool(row.get("isDelayed"))

		if not sport or not player or not event_id or not market or line is None:
			missing_required_fields += 1

		if game_status:
			status_counts[game_status] += 1
			if game_status not in {
				"scheduled",
				"live",
				"final",
				"postponed",
				"canceled",
				"delayed",
			}:
				issues["game_schedule"].append(
					f"Unknown status '{game_status}' for {player} {market}."
				)

		if start_time_utc:
			start_dt = _parse_start_time(start_time_utc)
			if start_dt is None:
				timezone_parse_failures += 1
			else:
				if start_dt.astimezone(_scoreboard_timezone()).date() < datetime.now(_scoreboard_timezone()).date():
					past_date_rows += 1
		else:
			timezone_parse_failures += 1

		if is_doubleheader:
			doubleheader_count += 1
		if is_neutral:
			neutral_site_count += 1
		if is_canceled:
			canceled_count += 1
		if is_delayed:
			delayed_count += 1

		if not player_id:
			missing_player_ids += 1
		else:
			name_to_ids[player].add(player_id)
		if identity_confidence < 0.8:
			weak_identity_rows += 1
		if injury_status == "unknown" and lineup_status == "unknown":
			unknown_availability_rows += 1

		matchup = str(row.get("matchup") or "")
		parts = matchup.split("@")
		if len(parts) == 2:
			away_raw = parts[0].strip()
			home_raw = parts[1].strip()
			away_norm = normalize_team_name(away_raw)
			home_norm = normalize_team_name(home_raw)
			team_alias_groups[away_norm].add(away_raw)
			team_alias_groups[home_norm].add(home_raw)

		normalized_category = normalize_market(market_key or market)
		if not normalized_category:
			unknown_categories += 1

		if recommended_side == "over" and edge_signed < 0:
			side_edge_mismatch += 1
		if recommended_side == "under" and edge_signed > 0:
			side_edge_mismatch += 1

		if over_odds is None or under_odds is None:
			missing_over_under_prices += 1

		if _is_stale_timestamp(last_updated, now_utc):
			stale_rows += 1

	for player_name, ids in name_to_ids.items():
		if len(ids) > 1:
			issues["player_matching"].append(
				f"Player '{player_name}' has multiple ids in feed: {sorted(ids)}"
			)

	for canonical_name, raw_names in team_alias_groups.items():
		if len(raw_names) > 1:
			issues["team_matching"].append(
				f"Team alias variants map to '{canonical_name}': {sorted(raw_names)}"
			)

	if past_date_rows > 0:
		issues["game_schedule"].append(
			f"Found {past_date_rows} prop rows with past local game date."
		)
	if timezone_parse_failures > 0:
		issues["game_schedule"].append(
			f"Found {timezone_parse_failures} rows with invalid or missing start time."
		)
	if missing_player_ids > 0:
		issues["player_matching"].append(
			f"Found {missing_player_ids} rows missing playerId."
		)
	if unknown_categories > 0:
		issues["prop_category"].append(
			f"Found {unknown_categories} rows with unknown normalized category."
		)
	if side_edge_mismatch > 0:
		issues["over_under"].append(
			f"Found {side_edge_mismatch} rows where recommended side conflicts with signed edge."
		)
	if missing_over_under_prices > 0:
		issues["odds_accuracy"].append(
			f"Found {missing_over_under_prices} rows missing over/under prices."
		)
	if stale_rows > 0:
		issues["freshness"].append(
			f"Found {stale_rows} stale rows older than 180 minutes by lastUpdatedUtc."
		)
	if weak_identity_rows > 0:
		issues["player_matching"].append(
			f"Found {weak_identity_rows} rows with weak identity confidence (< 0.8)."
		)
	if unknown_availability_rows > 0:
		issues["player_matching"].append(
			f"Found {unknown_availability_rows} rows without injury/lineup availability inputs."
		)

	warnings = {
		section: values[:30]
		for section, values in issues.items()
		if values
	}

	return {
		"status": "ok" if not warnings else "warning",
		"generatedAtUtc": now_utc.isoformat().replace("+00:00", "Z"),
		"summary": {
			"propCount": len(prop_rows),
			"missingRequiredFields": missing_required_fields,
			"statusCounts": dict(status_counts),
			"doubleheaderRows": doubleheader_count,
			"neutralSiteRows": neutral_site_count,
			"canceledRows": canceled_count,
			"delayedRows": delayed_count,
			"missingPlayerIds": missing_player_ids,
			"unknownCategories": unknown_categories,
			"sideEdgeMismatches": side_edge_mismatch,
			"missingOverUnderPrices": missing_over_under_prices,
			"staleRows": stale_rows,
			"weakIdentityRows": weak_identity_rows,
			"unknownAvailabilityRows": unknown_availability_rows,
			"pastDateRows": past_date_rows,
		},
		"warnings": warnings,
	}


@app.get("/api/identity/map")
def get_identity_map() -> dict[str, object]:
	return load_identity_map()


@app.post("/api/identity/bootstrap")
def bootstrap_identity_map(
	sourceProvider: str = Query(default="odds-api"),
) -> dict[str, object]:
	props = [item.model_dump() for item in get_props()]
	return bootstrap_identity_candidates(
		source_provider=sourceProvider,
		prop_rows=props,
	)


@app.get("/api/identity/unresolved")
def get_unresolved_identities(
	sourceProvider: str = Query(default="odds-api"),
	limit: int = Query(default=100),
) -> dict[str, object]:
	props = [item.model_dump() for item in get_props()]
	rows = unresolved_identity_rows(
		source_provider=sourceProvider,
		prop_rows=props,
		limit=max(1, min(limit, 500)),
	)
	return {
		"count": len(rows),
		"rows": rows,
	}


@app.get("/api/identity/unresolved-grouped")
def get_unresolved_identities_grouped(
	sourceProvider: str = Query(default="odds-api"),
	limit: int = Query(default=1000),
) -> dict[str, object]:
	props = [item.model_dump() for item in get_props()]
	rows = unresolved_identity_rows(
		source_provider=sourceProvider,
		prop_rows=props,
		limit=max(1, min(limit, 5000)),
	)
	row_lookup = {
		f"{str(item.get('source_player_id') or '')}|{str(item.get('player') or '')}": item
		for item in rows
	}
	grouped: dict[str, list[dict[str, str]]] = {}
	for prop in props:
		key = (
			f"{str(prop.get('sourcePlayerId') or prop.get('source_player_id') or '')}|"
			f"{str(prop.get('player') or '')}"
		)
		if key not in row_lookup:
			continue
		sport = str(prop.get("sport") or "UNKNOWN").strip() or "UNKNOWN"
		grouped.setdefault(sport, [])
		row = row_lookup[key]
		if row not in grouped[sport]:
			grouped[sport].append(row)

	for sport in grouped:
		grouped[sport] = sorted(
			grouped[sport],
			key=lambda value: str(value.get("player") or ""),
		)

	return {
		"count": sum(len(items) for items in grouped.values()),
		"sports": grouped,
	}


@app.post("/api/identity/map/bulk")
def bulk_identity_map_update(
	body: dict[str, object] = Body(default={}),
	mode: str = Query(default="merge"),
) -> dict[str, object]:
	normalized_mode = _normalize_bulk_mode(mode)
	incoming_providers = _validate_identity_bulk_body(body)
	payload = load_identity_map()

	if normalized_mode == "replace":
		payload = {"providers": {}}

	providers = payload.setdefault("providers", {})
	for provider_name, provider_map in incoming_providers.items():
		provider_key = str(provider_name).strip()
		target_map = providers.setdefault(provider_key, {})
		for source_player_id, entry in provider_map.items():
			raw_aliases = entry.get("aliases", [])
			aliases: list[str] = []
			if isinstance(raw_aliases, list):
				aliases = [
					str(item)
					for item in raw_aliases
					if str(item).strip()
				]
			target_map[str(source_player_id)] = {
				"canonical_player_id": str(
					entry.get("canonical_player_id") or ""
				).strip(),
				"full_name": str(entry.get("full_name") or "").strip(),
				"aliases": aliases,
			}

	save_identity_map(payload)
	provider_sizes = {
		provider: len(value)
		for provider, value in payload.get("providers", {}).items()
		if isinstance(value, dict)
	}
	return {
		"status": "saved",
		"mode": normalized_mode,
		"processedEntries": sum(
			len(value)
			for value in incoming_providers.values()
		),
		"providerSizes": provider_sizes,
	}


@app.put("/api/identity/map/{source_provider}/{source_player_id}")
def put_identity_mapping(
	source_provider: str,
	source_player_id: str,
	body: dict[str, object] = Body(default={}),
) -> dict[str, object]:
	try:
		raw_aliases = body.get("aliases", [])
		aliases: list[str] = []
		if isinstance(raw_aliases, list):
			aliases = [
				str(item)
				for item in raw_aliases
				if str(item).strip()
			]
		entry = upsert_identity_entry(
			source_provider=source_provider,
			source_player_id=source_player_id,
			canonical_player_id=str(body.get("canonical_player_id") or "").strip(),
			full_name=str(body.get("full_name") or "").strip(),
			aliases=aliases,
		)
		return {
			"status": "saved",
			"entry": entry,
		}
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/api/player-availability")
def get_player_availability_map() -> dict[str, object]:
	return load_status_map()


@app.post("/api/player-availability/bulk")
def bulk_player_availability_update(
	body: dict[str, object] = Body(default={}),
	mode: str = Query(default="merge"),
) -> dict[str, object]:
	normalized_mode = _normalize_bulk_mode(mode)
	incoming_players = _validate_availability_bulk_body(body)
	payload = load_status_map()

	if normalized_mode == "replace":
		payload = {"players": {}}

	players = payload.setdefault("players", {})
	for canonical_player_id, entry in incoming_players.items():
		canonical = str(canonical_player_id).strip()
		players[canonical] = {
			"injury_status": str(entry.get("injury_status") or "unknown").strip().lower(),
			"lineup_status": str(entry.get("lineup_status") or "unknown").strip().lower(),
			"notes": str(entry.get("notes") or "").strip(),
		}

	save_status_map(payload)
	return {
		"status": "saved",
		"mode": normalized_mode,
		"processedEntries": len(incoming_players),
		"count": len(players),
	}


@app.put("/api/player-availability/{canonical_player_id}")
def put_player_availability(
	canonical_player_id: str,
	body: dict[str, object] = Body(default={}),
) -> dict[str, object]:
	try:
		entry = upsert_player_availability(
			canonical_player_id=canonical_player_id,
			injury_status=str(body.get("injury_status") or "unknown"),
			lineup_status=str(body.get("lineup_status") or "unknown"),
			notes=str(body.get("notes") or ""),
		)
		return {
			"status": "saved",
			"entry": entry,
		}
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post(
	"/api/prop-builder",
	response_model=PropBuilderResponse,
)
def prop_builder(
	request: PropBuilderRequest,
) -> PropBuilderResponse:
	try:
		prop_list = get_props()
		prop_rows = []
		for prop in prop_list:
			row = prop.model_dump()
			prop_rows.append(
				{
					"id": row.get("id", ""),
					"event_id": row.get("eventId", ""),
					"api_sports_game_id": row.get(
						"apiSportsGameId",
						"",
					),
					"player": row.get("player", ""),
					"sport": row.get("sport", ""),
					"matchup": row.get("matchup", ""),
					"sportsbook": row.get("sportsbook", ""),
					"market": row.get("market", ""),
					"line": row.get("line", 0),
					"pick": row.get("pick", "OVER"),
					"edge": row.get("edge", 0),
					"confidence": row.get("edge", 0),
					"game_time": row.get("gameTime", ""),
					"image_path": row.get("imagePath", ""),
					"over_odds": row.get("overOdds"),
					"under_odds": row.get("underOdds"),
				}
			)

		result = build_prop_slip(
			request=request,
			prop_rows=prop_rows,
		)
		if result.generated_legs > 0:
			create_prop_builder_history(
				PropBuilderHistoryCreate(
					build_mode=result.build_mode,
					risk_mode=result.risk_mode,
					sports=result.sports,
					prop_sites=result.prop_sites,
					markets=result.markets,
					requested_legs=result.requested_legs,
					generated_legs=result.generated_legs,
					average_edge=result.average_edge,
					average_confidence=result.average_confidence,
					legs=[
						leg.model_dump()
						for leg in result.legs
					],
					status="pending",
					legs_pending=result.generated_legs,
				)
			)

		return result
	except ValueError as exc:
		raise HTTPException(
			status_code=400,
			detail=str(exc),
		) from exc
	except Exception as exc:
		raise HTTPException(
			status_code=500,
			detail=f"Unable to build prop slip: {exc}",
		) from exc


@app.post("/api/prop-builder/replace")
def replace_prop_builder_leg(
	request: PropReplacementRequest,
) -> dict[str, object]:
	prop_list = get_props()
	rows: list[dict[str, object]] = []
	for prop in prop_list:
		row = prop.model_dump()
		rows.append(
			{
				"id": row.get("id", ""),
				"event_id": row.get("eventId", ""),
				"api_sports_game_id": row.get(
					"apiSportsGameId",
					"",
				),
				"player": row.get("player", ""),
				"sport": row.get("sport", ""),
				"matchup": row.get("matchup", ""),
				"sportsbook": row.get("sportsbook", ""),
				"market": row.get("market", ""),
				"line": row.get("line", 0),
				"pick": row.get("pick", "OVER"),
				"edge": row.get("edge", 0),
				"confidence": row.get("edge", 0),
				"game_time": row.get("gameTime", ""),
				"image_path": row.get("imagePath", ""),
				"over_odds": row.get("overOdds"),
				"under_odds": row.get("underOdds"),
			}
		)

	replacement = replace_prop_leg(
		request=request,
		prop_rows=rows,
	)
	if replacement is None:
		raise HTTPException(
			status_code=404,
			detail=(
				"No replacement prop matched "
				"the selected filters."
			),
		)

	return {
		"replacement": replacement.model_dump(),
	}


@app.post(
	"/api/prop-builder/check-lines",
	response_model=PropLineMovementResponse,
)
def check_builder_lines(
	request: PropLineMovementRequest,
	refresh: bool = False,
) -> PropLineMovementResponse:
	if refresh:
		if not _sync_is_fresh() and _sync_run_lock.acquire(blocking=False):
			_mark_sync_running()
			_run_sync_background()

	prop_list = get_props()
	rows: list[dict[str, object]] = []
	for prop in prop_list:
		row = prop.model_dump()
		rows.append(
			{
				"id": row.get("id", ""),
				"event_id": row.get("eventId", ""),
				"api_sports_game_id": row.get(
					"apiSportsGameId",
					"",
				),
				"player": row.get("player", ""),
				"sport": row.get("sport", ""),
				"matchup": row.get("matchup", ""),
				"sportsbook": row.get("sportsbook", ""),
				"market": row.get("market", ""),
				"line": row.get("line", 0),
				"odds": row.get("odds"),
				"over_odds": row.get("overOdds"),
				"under_odds": row.get("underOdds"),
			}
		)

	return check_prop_line_movement(
		legs=request.legs,
		prop_rows=rows,
	)


@app.get(
	"/api/prop-builder/presets",
	response_model=list[PropBuilderPreset],
)
def get_prop_builder_presets() -> list[PropBuilderPreset]:
	return list_prop_builder_presets()


@app.post(
	"/api/prop-builder/presets",
	response_model=PropBuilderPreset,
)
def save_prop_builder_preset(
	preset: PropBuilderPresetCreate,
) -> PropBuilderPreset:
	return create_prop_builder_preset(preset)


@app.delete("/api/prop-builder/presets/{preset_id}")
def remove_prop_builder_preset(
	preset_id: int,
) -> dict[str, object]:
	deleted = delete_prop_builder_preset(
		preset_id
	)
	if not deleted:
		raise HTTPException(
			status_code=404,
			detail="Preset not found.",
		)

	return {
		"deleted": True,
		"preset_id": preset_id,
	}


@app.get(
	"/api/prop-builder/history",
	response_model=list[PropBuilderHistory],
)
def get_builder_history(
	limit: int = 30,
) -> list[PropBuilderHistory]:
	return list_prop_builder_history(
		limit=limit,
	)


@app.get(
	"/api/prop-builder/performance",
	response_model=PropBuilderPerformanceResponse,
)
def prop_builder_performance(
	recent_limit: int = 10,
	days: int | None = None,
	sport: str | None = None,
	prop_site: str | None = None,
	market: str | None = None,
) -> PropBuilderPerformanceResponse:
	safe_days = None
	if days is not None:
		safe_days = max(
			1,
			min(days, 3650),
		)

	return get_prop_builder_performance(
		recent_limit=max(
			1,
			min(recent_limit, 50),
		),
		days=safe_days,
		sport=sport,
		prop_site=prop_site,
		market=market,
	)


@app.post(
	"/api/prop-builder/history/grade",
)
def grade_builder_history() -> dict[str, object]:
	try:
		result = grade_prop_builder_history()
		return {
			"status": "complete",
			**result,
		}
	except Exception as exc:
		raise HTTPException(
			status_code=500,
			detail=(
				"Builder history grading failed: "
				f"{exc}"
			),
		) from exc


@app.get(
	"/api/prop-builder/strategy",
	response_model=PropBuilderStrategyResponse,
)
def prop_builder_strategy() -> PropBuilderStrategyResponse:
	return get_prop_builder_strategy()


@app.get(
	"/api/prop-builder/history/{history_id}",
	response_model=PropBuilderHistory,
)
def get_builder_history_item(
	history_id: int,
) -> PropBuilderHistory:
	build = get_prop_builder_history(
		history_id
	)
	if build is None:
		raise HTTPException(
			status_code=404,
			detail="Build history item not found.",
		)

	return build


@app.delete(
	"/api/prop-builder/history/{history_id}",
)
def remove_builder_history_item(
	history_id: int,
) -> dict[str, object]:
	deleted = delete_prop_builder_history(
		history_id
	)
	if not deleted:
		raise HTTPException(
			status_code=404,
			detail="Build history item not found.",
		)

	return {
		"deleted": True,
		"history_id": history_id,
	}


@app.delete(
	"/api/prop-builder/history",
)
def remove_all_builder_history() -> dict[str, object]:
	deleted_count = clear_prop_builder_history()
	return {
		"deleted": True,
		"deleted_count": deleted_count,
	}


@app.post("/api/slips/preview")
def preview_slip(
	request: SlipPreview,
) -> dict[str, float]:
	slip_request = SlipCreate(
		legs=request.legs,
		stake=request.stake,
	)
	payout = calculate_payout_preview(slip_request)
	return {
		"stake": request.stake,
		"potential_payout": payout,
		"potential_profit": round(
			payout - request.stake,
			2,
		),
	}


@app.post("/api/slips")
def save_slip(request: SlipCreate, user_id: str = Depends(require_user_id)) -> dict[str, object]:
	slip = create_slip(request, user_id=user_id)
	realtime_hub.broadcast_user_from_thread(
		{"type": "ticket.updated", "version": 1, "eventId": f"ticket-{slip.id}",
		 "occurredAt": datetime.now(timezone.utc).isoformat(), "data": slip.model_dump(mode="json")},
		"tickets", user_id,
	)
	return {
		"status": "saved",
		"slip": slip.model_dump(),
	}


@app.get("/api/slips")
def list_slips(
	status: str | None = Query(default=None),
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	slips = get_slips(status, user_id=user_id)
	return {
		"count": len(slips),
		"slips": [
			slip.model_dump()
			for slip in slips
		],
	}


@app.get("/api/active-ticket")
def get_active_ticket(
	season: str = Query(default=str(datetime.now().year)),
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	return _active_ticket_payload(season=season, user_id=user_id)


@app.patch("/api/slips/{slip_id}/status")
def change_slip_status(
	slip_id: str,
	status: str,
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	try:
		updated = update_slip_status(
			slip_id,
			status,
			user_id=user_id,
		)
	except ValueError as exc:
		raise HTTPException(
			status_code=400,
			detail=str(exc),
		) from exc

	if not updated:
		raise HTTPException(
			status_code=404,
			detail="Slip not found.",
		)

	realtime_hub.broadcast_user_from_thread(
		{"type": "ticket.updated", "version": 1, "eventId": f"ticket-{slip_id}-{status}",
		 "occurredAt": datetime.now(timezone.utc).isoformat(),
		 "data": {"id": slip_id, "status": status}}, "tickets", user_id,
	)

	return {
		"status": "updated",
		"slip_id": slip_id,
		"new_status": status,
	}


@app.post("/api/slips/results")
def process_slip_results(
	updates: list[LegResultUpdate],
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	updated = update_slip_results(updates, user_id=user_id)
	return {
		"status": "complete",
		"updated_slips": updated,
	}


@app.get("/api/scores/{sport_key}")
def scores(
	sport_key: str,
	days_from: int = 1,
) -> dict[str, object]:
	try:
		results = fetch_scores(
			sport_key,
			days_from=days_from,
		)
		return {
			"count": len(results),
			"scores": results,
		}
	except Exception as exc:
		raise HTTPException(
			status_code=500,
			detail=f"Unable to load scores: {exc}",
		) from exc


@app.get("/api/scoreboard")
def scoreboard(
	game_date: str | None = Query(
		default=None,
		alias="date",
	),
) -> dict[str, object]:
	if game_date is None or game_date.strip() == "":
		target_date = date.today()
	else:
		try:
			target_date = date.fromisoformat(
				game_date.strip()
			)
		except ValueError as exc:
			raise HTTPException(
				status_code=400,
				detail="date must be YYYY-MM-DD",
			) from exc

	now = datetime.now(timezone.utc)
	shared_time_map = _shared_game_time_map()
	games: list[dict[str, object]] = []

	def load_sport(
		league_and_key: tuple[str, str],
	) -> list[dict[str, object]]:
		league, sport_key = league_and_key
		return _scoreboard_games_for_sport(
			league=league,
			sport_key=sport_key,
			target_date=target_date,
			now=now,
			shared_time_map=shared_time_map,
		)

	with ThreadPoolExecutor(
		max_workers=len(SCOREBOARD_SPORT_KEYS)
	) as executor:
		for sport_games in executor.map(
			load_sport,
			SCOREBOARD_SPORT_KEYS,
		):
			games.extend(sport_games)

	deduped: dict[str, dict[str, object]] = {}
	for game in games:
		key = (
			f"{str(game.get('league', ''))}|"
			f"{str(game.get('away_team', ''))}|"
			f"{str(game.get('home_team', ''))}"
		)
		existing = deduped.get(key)
		if existing is None or _scoreboard_preference(game) >= _scoreboard_preference(existing):
			deduped[key] = game

	games = list(deduped.values())

	games.sort(
		key=lambda game: (
			str(game.get("sport", "")),
			str(game.get("start_time", "")),
		)
	)

	realtime_hub.broadcast_from_thread(
		{"type": "scoreboard.updated", "version": 1,
		 "eventId": f"scoreboard-{target_date.isoformat()}-{int(now.timestamp())}",
		 "occurredAt": now.isoformat(),
		 "data": {"date": target_date.isoformat(), "games": games}},
		"scoreboard",
	)

	return {
		"date": target_date.isoformat(),
		"updated_at": now.isoformat(),
		"games": games,
	}


@app.post("/api/slips/{slip_id}/closing-lines")
def save_slip_closing_lines(
	slip_id: str,
	request: SlipClosingLinesUpdate,
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	result = update_slip_closing_lines(slip_id, request.updates, user_id)
	if result is None:
		raise HTTPException(status_code=404, detail="Slip not found.")
	realtime_hub.broadcast_user_from_thread(
		{"type": "ticket.clv_updated", "version": 1,
		 "eventId": f"ticket-{slip_id}-clv",
		 "occurredAt": datetime.now(timezone.utc).isoformat(), "data": result},
		"tickets", user_id,
	)
	return result


@app.post("/api/slips/game-status/refresh")
def refresh_slip_game_statuses(
	days_from: int = 1,
	_user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	try:
		results = refresh_saved_slip_game_statuses(
			days_from=days_from,
		)
		return {
			"status": "complete",
			"results": results,
		}
	except Exception as exc:
		raise HTTPException(
			status_code=500,
			detail=(
				"Unable to refresh slip game status: "
				f"{exc}"
			),
		) from exc


@app.post("/api/slips/refresh-games/{sport_key}")
def refresh_slip_games(
	sport_key: str,
	_user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	try:
		scores = fetch_scores(
			sport_key,
			days_from=2,
		)
		updated = update_slip_game_statuses(
			scores
		)
		return {
			"status": "complete",
			"scores_found": len(scores),
			"updated_slips": updated,
		}
	except Exception as exc:
		raise HTTPException(
			status_code=500,
			detail=(
				"Unable to refresh slip games: "
				f"{exc}"
			),
		) from exc


@app.post("/api/slips/grade-test/{sport_key}/{event_id}")
def grade_test(
	sport_key: str,
	event_id: str,
	_admin: str = Depends(require_admin),
) -> dict[str, object]:
	provider = MockPlayerStatsProvider()
	updated = grade_event_slips(
		sport_key=sport_key,
		event_id=event_id,
		provider=provider,
	)
	return {
		"status": "complete",
		"updated_slips": updated,
	}


@app.get("/api/providers/api-sports/status")
def api_sports_status() -> dict[str, object]:
	provider = ApiSportsBasketballProvider()
	payload = provider.status()
	return {
		"connected": True,
		"provider": "API-Sports Basketball",
		"response": payload,
	}


@app.get("/api/providers/api-sports/wnba")
def api_sports_wnba() -> dict[str, object]:
	provider = ApiSportsBasketballProvider()
	payload = provider.find_wnba_leagues()
	return {
		"provider": "API-Sports Basketball",
		"response": payload,
	}


@app.get("/api/providers/api-sports/wnba/games/{season}")
def api_sports_wnba_games(
	season: str,
) -> dict[str, object]:
	if not WNBA_LEAGUE_ID:
		raise HTTPException(
			status_code=500,
			detail="WNBA_LEAGUE_ID is missing.",
		)

	provider = ApiSportsBasketballProvider()
	return {
		"provider": "API-Sports Basketball",
		"response": provider.get_games(
			league_id=WNBA_LEAGUE_ID,
			season=season,
		),
	}


@app.get("/api/providers/api-sports/wnba/game/{game_id}/players")
def api_sports_wnba_player_stats(
	game_id: str,
) -> dict[str, object]:
	provider = ApiSportsBasketballProvider()
	payload = provider.get_game_player_statistics(
		game_id=game_id,
	)
	return {
		"provider": "API-Sports Basketball",
		"game_id": game_id,
		"response": payload,
	}


@app.post("/api/providers/api-sports/wnba/map-event")
def map_wnba_event_endpoint(
	odds_event_id: str,
	home_team: str,
	away_team: str,
	commence_time: str,
	season: str = "2026",
) -> dict[str, object]:
	matched_id = map_wnba_event(
		odds_event_id=odds_event_id,
		home_team=home_team,
		away_team=away_team,
		commence_time=commence_time,
		season=season,
	)
	return {
		"matched": matched_id is not None,
		"odds_event_id": odds_event_id,
		"api_sports_game_id": matched_id,
	}


@app.post("/api/slips/grade-wnba")
def grade_wnba_slips(_user_id: str = Depends(require_user_id)) -> dict[str, object]:
	try:
		result = grade_active_wnba_slips()
		return {
			"status": "complete",
			**result,
		}
	except Exception as exc:
		raise HTTPException(
			status_code=500,
			detail=f"WNBA grading failed: {exc}",
		) from exc


@app.get("/api/slips/diagnose-wnba/{game_id}")
def diagnose_wnba(
	game_id: str,
	_admin: str = Depends(require_admin),
) -> dict[str, object]:
	try:
		report = diagnose_wnba_game(game_id)
		return report.model_dump()
	except Exception as exc:
		raise HTTPException(
			status_code=500,
			detail=f"WNBA diagnosis failed: {exc}",
		) from exc
