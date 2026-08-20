import asyncio
import hashlib
import json
import logging
import os
import time
from urllib.parse import urljoin, urlparse
from pathlib import Path
from contextlib import asynccontextmanager, suppress
from typing import Callable
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone, tzinfo
from collections import Counter, defaultdict
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import BackgroundTasks, Body, Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse
from brotli_asgi import BrotliMiddleware
import requests
from threading import Event, Lock, Thread

from config import (
	BALLDONTLIE_API_KEY,
	CORS_ALLOWED_ORIGINS,
	HTTP_TIMEOUT_SECONDS,
	LIVE_ODDS_SYNC_MIN_SECONDS,
	PREFERRED_BOOKMAKERS,
	PLAYER_IMAGE_DIR,
	SPORTRADAR_API_KEY,
	SPORTRADAR_WNBA_API_KEY,
	WNBA_LEAGUE_ID,
)
from database.postgres import (
	check_database_connection,
	close_database_pool,
	database_is_configured,
	database_performance_snapshot,
)
from models.prop_builder import (
	PropBuilderRequest,
	PropBuilderResponse,
	PropReplacementRequest,
)
from models.prop import PropResponse
from models.prop_access import core_prop_payload
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
from models.slip import (
	LegResultUpdate,
	SlipClosingLinesUpdate,
	SlipCreate,
	SlipPreview,
	SlipResponse,
)
from providers.api_sports_basketball import (
	ApiSportsBasketballProvider,
)
from providers.api_sports_baseball import ApiSportsBaseballProvider
from providers.mock_player_stats import MockPlayerStatsProvider
from services.automatic_grader import grade_event_slips
from services.game_status_service import (
	refresh_saved_slip_game_statuses,
)
from services.baseline_projection_service import (
	MODEL_VERSION as BASELINE_MODEL_VERSION,
)
from services.odds_service import sport_coverage
from services.line_movement_recorder import record_line_movements
from services.operations_notification_service import alert_channel_health
from services.prop_group_service import assign_prop_groups
from services.prop_service import get_props
from services.formatters import resolve_player_image
from services.owner_action_service import filter_owner_quarantined_props
from services.provider_reliability_service import build_provider_reliability
from services.pi_verdict_service import compute_verdict, verdict_payload
from services.daily_briefing_service import build_briefing
from services.projection_backtest_service import (
	grade_sport,
	projection_grade_snapshot as _projection_grade_snapshot,
)
from services.selectability_projection_service import (
	selectability_projection as _selectability_projection,
)
from services.prediction_automation_service import (
	snapshot_probability_sources as _snapshot_probability_sources,
)
from services.public_track_record_service import (
	last_failure as track_record_last_failure,
	public_track_record,
)
from services.distributed_cache_service import (
	delete as delete_distributed_cache,
	get_compressed_json as get_distributed_compressed_json,
	get_json as get_distributed_json,
	health as distributed_cache_health,
	last_write_error as distributed_cache_last_write_error,
	set_compressed_json_streaming_list as set_distributed_compressed_catalog,
	set_json as set_distributed_json,
	set_json_streaming_list as set_distributed_json_streaming_list,
)
from services.job_queue_service import (
	acquire_global_sync_lock,
	enqueue as enqueue_background_job,
	health as job_queue_health,
	job_status as background_job_status,
	refresh_global_sync_lock,
	release_global_sync_lock,
)
from services.injury_impact_alert_service import (
	evaluate_injury_impact_changes,
	injury_alert_history,
)
from services.prop_catalog_snapshot_service import (
	load_catalog_snapshot,
	catalog_snapshot_status,
	save_catalog_snapshot,
	snapshot_is_behind,
)
from services.raw_ingestion_service import health as ingestion_pipeline_health
from services.rate_limit_service import allow_request
from services.security_event_service import record_security_event
from services.scoreboard_metrics_service import record_scoreboard_request
from services.market_intelligence_service import latest_market_intelligence
from services.espn_headshot_service import (
	espn_headshot_cache_health,
)
from services.historical_ingestion_service import (
	run_gridiron_ice_backfill,
)
from services.sportsdataio_golf_service import refresh_golf_roster_map
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
from services.odds_service import (
	active_key_snapshot,
	historical_access,
	bookmaker_coverage,
	fetch_events,
	quota_snapshot,
)
from providers.sportsgameodds import usage_snapshot as sportsgameodds_usage
from services.game_market_service import get_game_markets, game_market_health
from services.slip_service import (
	capture_closing_lines_from_props,
	slip_storage_health,
	calculate_payout_preview,
	create_slip,
	delete_slip,
	get_slips,
	migrate_legacy_sqlite_slips,
	update_slip_game_statuses,
	update_slip_closing_lines,
	update_slip_results,
	update_slip_status,
)
from services.live_stats_service import get_live_player_stat_snapshot
from services.multi_sport_grading_service import grade_active_slips
from models.sync_diagnostic import TicketSyncDiagnostic
from services.sync_diagnostic_service import record_ticket_sync_diagnostic
from services.sync_certification_service import sync_certification
from services.result_reconciliation_service import reconcile_user_slips
from services.prediction_automation_service import prediction_calibration_report
from services.runtime_readiness_service import runtime_readiness
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
from services.api_auth_service import (
	AccessLevel,
	Membership,
	require_core,
	require_owner,
	require_pro,
	require_user_id,
)
from routers.intelligence import router as intelligence_router
from routers.billing import router as billing_router
from routers.realtime import hub as realtime_hub, router as realtime_router
from routers.discord_chat import router as discord_chat_router
from routers.operations import router as operations_router
from services.discord_bridge_service import discord_bridge

logging.basicConfig(
	level=logging.INFO,
	format=(
		"%(asctime)s | %(levelname)s | "
		"%(name)s | %(message)s"
	),
)


async def _warm_prop_catalog_before_ready() -> int:
	"""Hydrate the durable catalog before Render routes customer traffic."""
	try:
		warm_props = await asyncio.wait_for(
			asyncio.to_thread(_cached_prop_catalog),
			timeout=20,
		)
		logging.info("Startup prop catalog warm props=%s", len(warm_props))
		return len(warm_props)
	except TimeoutError:
		logging.warning("Startup prop catalog warm timed out; continuing safely")
	except Exception:
		logging.exception(
			"Startup prop catalog warm failed; durable fallback remains available"
		)
	return 0


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
	logging.info(
		"Legacy ticket import result=%s",
		migrate_legacy_sqlite_slips(),
	)
	# Hydrate the saved catalog before Render marks this instance ready. A cold
	# request otherwise becomes the thread that decodes and validates 10k+ rows,
	# leaving a signed-in customer on skeleton cards for several seconds.
	await _warm_prop_catalog_before_ready()
	startup_sync_task = asyncio.create_task(_ensure_props_available())
	freshness_watchdog_task = asyncio.create_task(_maintain_prop_freshness())
	discord_bridge.set_message_handler(
		lambda event: realtime_hub.broadcast(event, "chat")
	)
	await discord_bridge.start()
	try:
		yield
	finally:
		await discord_bridge.stop()
		for task in (startup_sync_task, freshness_watchdog_task):
			task.cancel()
		for task in (startup_sync_task, freshness_watchdog_task):
			with suppress(asyncio.CancelledError):
				await task
		close_database_pool()

app = FastAPI(
	title="PROP INTELLIGENCE API",
	version="1.2.0",
	lifespan=lifespan,
)

APP_VERSION = os.getenv("RENDER_GIT_COMMIT", os.getenv("APP_VERSION", "development"))
_prop_catalog_lock = Lock()
_prop_catalog_load_lock = Lock()
# Ordered from freshest to most degraded.
_CATALOG_SOURCE_LIVE = "live"
_CATALOG_SOURCE_SHARED = "shared-cache"
_CATALOG_SOURCE_RECOVERY = "durable-snapshot"
_CATALOG_SOURCE_EMPTY = "unavailable"
_RECOVERY_SOURCES = frozenset({_CATALOG_SOURCE_RECOVERY})


_prop_catalog: dict[str, object] = {
	"loadedAt": 0.0,
	"versionCheckedAt": 0.0,
	"version": None,
	"props": [],
	# Which layer produced the props currently held. The board looked
	# identical whether it came from a live sync or from a day-old durable
	# snapshot, so a stalled feed presented as a healthy one -- exactly what
	# happened while catalog publication was failing for six hours.
	"source": _CATALOG_SOURCE_EMPTY,
}
_prop_metrics_lock = Lock()
_prop_metrics: dict[str, object] = {
	"requests": 0,
	"errors": 0,
	"emptyResponses": 0,
	"lastDurationMs": 0,
	"lastPayloadBytes": 0,
	"lastServedAt": None,
	"lastTotalCount": 0,
	"lastDataUpdatedAt": None,
	"lastRequestSucceeded": None,
	"cacheHits": 0,
}
_PROP_CATALOG_KEY = "props:catalog:v1"
# The v1 payload was stored uncompressed and grew to roughly 112 MiB, which
# the atomic rename doubles at publication time. v2 holds the same catalog
# zlib-compressed. Both are read during a rollout so instances on either
# release keep serving a shared catalog instead of falling back to the
# durable snapshot; only v2 is ever written.
_PROP_CATALOG_COMPRESSED_KEY = "props:catalog:v2"
_PROP_CATALOG_VERSION_KEY = "props:catalog:version:v1"
_PROP_CATALOG_SUMMARY_KEY = "props:catalog:summary:v1"
_PROP_RESPONSE_CACHE_TTL_SECONDS = 20
_PROP_RESPONSE_CACHE_MAX_ENTRIES = 256
_prop_response_cache_lock = Lock()
_prop_response_cache: dict[str, tuple[float, str, dict[str, object]]] = {}


def _cached_prop_response(
	cache_key: str,
) -> tuple[str, dict[str, object]] | None:
	now = time.monotonic()
	with _prop_response_cache_lock:
		cached = _prop_response_cache.get(cache_key)
		if cached is None:
			return None
		expires_at, etag, payload = cached
		if expires_at <= now:
			_prop_response_cache.pop(cache_key, None)
			return None
		return etag, payload


def _remember_prop_response(
	cache_key: str,
	*,
	etag: str,
	payload: dict[str, object],
) -> None:
	now = time.monotonic()
	with _prop_response_cache_lock:
		if len(_prop_response_cache) >= _PROP_RESPONSE_CACHE_MAX_ENTRIES:
			expired = [
				key
				for key, (expires_at, _etag, _payload) in _prop_response_cache.items()
				if expires_at <= now
			]
			for key in expired:
				_prop_response_cache.pop(key, None)
			if len(_prop_response_cache) >= _PROP_RESPONSE_CACHE_MAX_ENTRIES:
				_prop_response_cache.clear()
		_prop_response_cache[cache_key] = (
			now + _PROP_RESPONSE_CACHE_TTL_SECONDS,
			etag,
			payload,
		)


app.include_router(intelligence_router)
app.include_router(billing_router)
app.include_router(realtime_router)
app.include_router(discord_chat_router)
app.include_router(operations_router)

app.add_middleware(
	CORSMiddleware,
	allow_origins=CORS_ALLOWED_ORIGINS,
	allow_origin_regex=r"https://([a-z0-9-]+\.)?propsintell\.com",
	allow_credentials=False,
	allow_methods=["*"],
	allow_headers=["*"],
)
app.add_middleware(BrotliMiddleware, minimum_size=1000, quality=4)
app.add_middleware(GZipMiddleware, minimum_size=1000, compresslevel=5)

def _rate_limit_scope(request: Request) -> tuple[str, int] | None:
	path = request.url.path
	method = request.method.upper()
	if path.startswith("/api/intelligence") or path in {
		"/api/props/ev",
		"/api/props/calibration",
		"/api/prop-alerts",
	}:
		return "pro-calculation", 30
	if path == "/api/props" and request.query_params.get("search", "").strip():
		return "player-search", 30
	if path.startswith("/api/props"):
		return "prop-feed", 60
	if path == "/api/slips" and method == "POST":
		return "ticket-create", 10
	if path.startswith("/api/slips") or path == "/api/active-ticket":
		return "tickets", 60
	if path.startswith("/api/realtime"):
		return "chat-realtime", 30
	if path.startswith("/api/scoreboard") or path.startswith("/api/scores"):
		return "scoreboard", 60
	return None


def _queue_security_event(event_type: str, **kwargs: object) -> None:
	"""Keep security persistence off the request's latency-sensitive path."""
	asyncio.create_task(
		asyncio.to_thread(record_security_event, event_type, **kwargs)
	)


@app.middleware("http")
async def protect_premium_api(request: Request, call_next: Callable):
	"""Throttle valuable datasets and apply browser-safe response headers."""
	path = request.url.path
	request_started = time.perf_counter()
	rate_limit = _rate_limit_scope(request)
	if rate_limit is not None:
		scope, scoped_limit = rate_limit
		authorization = request.headers.get("authorization", "")
		authenticated = authorization.lower().startswith("bearer ")
		identity = authorization if authenticated else (
			request.headers.get("cf-connecting-ip")
			or (request.client.host if request.client else "unknown")
		)
		allowed, remaining, limit = allow_request(
			f"{scope}:{identity}",
			authenticated=authenticated,
			limit=scoped_limit if authenticated else min(scoped_limit, 20),
		)
		if not allowed:
			_queue_security_event(
				"rate_limit_blocked",
				identity=identity,
				route=path,
				method=request.method,
				outcome="blocked",
				metadata={"scope": scope, "limit": limit},
			)
			return Response(
				content='{"detail":"Request limit reached. Try again shortly."}',
				status_code=429,
				media_type="application/json",
				headers={
					"Retry-After": "60",
					"X-RateLimit-Limit": str(limit),
					"X-RateLimit-Remaining": "0",
					"Cache-Control": "no-store",
				},
			)
		response = await call_next(request)
		response.headers["X-RateLimit-Limit"] = str(limit)
		response.headers["X-RateLimit-Remaining"] = str(remaining)
		response.headers["Cache-Control"] = "private, no-store, max-age=0"
		if response.status_code in {401, 403}:
			_queue_security_event(
				"subscription_or_access_denied",
				identity=identity,
				route=path,
				method=request.method,
				outcome=str(response.status_code),
				metadata={"scope": scope},
			)
		elif (
			scope in {"pro-calculation", "ticket-create"}
			and response.status_code < 400
		):
			_queue_security_event(
				"protected_feature_access",
				identity=identity,
				route=path,
				method=request.method,
				outcome="allowed",
				metadata={"scope": scope},
			)
	else:
		response = await call_next(request)
	response.headers["X-Content-Type-Options"] = "nosniff"
	response.headers["X-Frame-Options"] = "DENY"
	response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
	response.headers["Permissions-Policy"] = (
		"camera=(), microphone=(), geolocation=(), payment=(self)"
	)
	response.headers["Strict-Transport-Security"] = (
		"max-age=31536000; includeSubDomains"
	)
	if path == "/api/scoreboard":
		record_scoreboard_request(
			(time.perf_counter() - request_started) * 1000,
			succeeded=response.status_code < 500,
		)
	return response


@app.get("/player-images/{filename}", include_in_schema=False)
def player_image(filename: str) -> FileResponse:
	path = PLAYER_IMAGE_DIR / filename
	if path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"} or not path.is_file():
		raise HTTPException(status_code=404, detail="Player image not found")
	return FileResponse(
		path,
		headers={"Cache-Control": "public, max-age=604800, stale-while-revalidate=86400"},
	)


_PLAYER_IMAGE_PROXY_HOSTS = {"a.espncdn.com", "img.mlbstatic.com"}
_PLAYER_IMAGE_MAX_BYTES = 5 * 1024 * 1024


def _validated_player_image_url(value: str) -> str:
	parsed = urlparse(value)
	if (
		parsed.scheme != "https"
		or parsed.hostname is None
		or parsed.hostname.lower() not in _PLAYER_IMAGE_PROXY_HOSTS
		or parsed.username is not None
		or parsed.password is not None
	):
		raise HTTPException(status_code=400, detail="Unsupported player image URL")
	return value


@app.get("/player-image-proxy", include_in_schema=False)
def player_image_proxy(url: str = Query(..., max_length=2048)) -> Response:
	current_url = _validated_player_image_url(url)
	upstream = None
	for _redirect in range(3):
		for attempt in range(2):
			try:
				upstream = requests.get(
					current_url,
					headers={"User-Agent": "PropIntelligence/1.0"},
					timeout=HTTP_TIMEOUT_SECONDS,
					allow_redirects=False,
				)
				break
			except requests.RequestException:
				if attempt == 1:
					raise HTTPException(
						status_code=502,
						detail="Player image provider unavailable",
					)
		if upstream is None:
			raise HTTPException(status_code=502, detail="Player image provider unavailable")
		if upstream.is_redirect:
			location = upstream.headers.get("location")
			if not location:
				raise HTTPException(status_code=502, detail="Invalid image redirect")
			current_url = _validated_player_image_url(urljoin(current_url, location))
			continue
		break
	else:
		raise HTTPException(status_code=502, detail="Too many image redirects")

	if upstream.status_code != 200:
		raise HTTPException(status_code=upstream.status_code, detail="Player image unavailable")
	content_type = upstream.headers.get("content-type", "").split(";", 1)[0].lower()
	if content_type not in {"image/jpeg", "image/png", "image/webp"}:
		raise HTTPException(status_code=502, detail="Invalid player image response")
	if len(upstream.content) > _PLAYER_IMAGE_MAX_BYTES:
		raise HTTPException(status_code=502, detail="Player image is too large")
	return Response(
		content=upstream.content,
		media_type=content_type,
		headers={
			"Cache-Control": "public, max-age=604800, stale-while-revalidate=86400",
			"X-Content-Type-Options": "nosniff",
		},
	)


def _persist_catalog_snapshot_background(props: list[PropResponse]) -> None:
	try:
		if not snapshot_is_behind(props):
			return
		save_catalog_snapshot([prop.model_dump(mode="json") for prop in props])
	except Exception:
		logging.exception("Background prop catalog snapshot persist failed")


def _recompute_runtime_verdicts(
	props: list[PropResponse],
) -> list[PropResponse]:
	"""Refresh code-derived verdicts after hydrating a cached catalog.

	Redis and the durable snapshot store complete prop payloads, including the
	verdict produced by the release that wrote them. Reusing that field after a
	deploy leaves new verdict formulas invisible until the next odds sync.
	The same snapshots can retain old bundled action photos even after an
	official headshot becomes available. Upgrade only empty/local image paths;
	a valid remote provider image is preserved.
	"""
	resolved_images: dict[tuple[str, str], str] = {}
	for prop in props:
		prop.verdict = verdict_payload(compute_verdict(prop))
		current_image = str(getattr(prop, "imagePath", "") or "").strip()
		uses_local_image = (
			not current_image
			or current_image.startswith("/player-images/")
			or current_image.startswith("assets/players/")
		)
		uses_refreshable_provider_image = current_image.startswith((
			"https://a.espncdn.com/",
			"https://img.mlbstatic.com/",
		))
		if uses_local_image or uses_refreshable_provider_image:
			key = (prop.player.strip().lower(), prop.sport.strip().upper())
			if key not in resolved_images:
				resolved_images[key] = resolve_player_image(prop.player, prop.sport)
			resolved = resolved_images[key]
			if resolved:
				prop.imagePath = resolved
	return props


def _cached_prop_catalog() -> list[PropResponse]:
	# Only the cache lookup/hydration is serialized; callers release this lock
	# before filtering or building their response. This prevents concurrent
	# cold-start requests from each decoding and validating the full catalog.
	with _prop_catalog_load_lock:
		return _cached_prop_catalog_singleflight()


def _cached_prop_catalog_singleflight() -> list[PropResponse]:
	now = time.monotonic()
	with _prop_catalog_lock:
		loaded_at = float(_prop_catalog["loadedAt"] or 0.0)
		version_checked_at = float(
			_prop_catalog["versionCheckedAt"] or 0.0
		)
		cached_version = _prop_catalog["version"]
		cached = _prop_catalog["props"]
		if (
			isinstance(cached, list)
			and cached
			and now - version_checked_at < 10
		):
			return filter_owner_quarantined_props(cached)
	shared_version = get_distributed_json(_PROP_CATALOG_VERSION_KEY)
	if isinstance(cached, list) and cached:
		if (
			shared_version is None
			and now - loaded_at < 300
		) or shared_version == cached_version:
			with _prop_catalog_lock:
				_prop_catalog["versionCheckedAt"] = now
			return filter_owner_quarantined_props(cached)
	shared = get_distributed_compressed_json(_PROP_CATALOG_COMPRESSED_KEY)
	if not (isinstance(shared, list) and shared):
		shared = get_distributed_json(_PROP_CATALOG_KEY)
	if isinstance(shared, list) and shared:
		try:
			props = _recompute_runtime_verdicts(
				[PropResponse.model_validate(row) for row in shared]
			)
			# A live request must never block on a Postgres write. Persist the
			# durable recovery snapshot off the request thread; it is
			# best-effort already (save_catalog_snapshot swallows its own
			# errors) so losing the return value here changes nothing.
			Thread(
				target=_persist_catalog_snapshot_background,
				args=(props,),
				daemon=True,
			).start()
			_publish_prop_catalog_summary(props)
			with _prop_catalog_lock:
				_prop_catalog.update(
					loadedAt=now,
					versionCheckedAt=now,
					version=shared_version or "unversioned",
					props=props,
					source=_CATALOG_SOURCE_SHARED,
				)
			return filter_owner_quarantined_props(props)
		except Exception:
			delete_distributed_cache(_PROP_CATALOG_COMPRESSED_KEY)
			delete_distributed_cache(_PROP_CATALOG_KEY)
	durable = load_catalog_snapshot()
	if durable:
		try:
			props = _recompute_runtime_verdicts(
				[PropResponse.model_validate(row) for row in durable]
			)
			with _prop_catalog_lock:
				_prop_catalog.update(
					loadedAt=now,
					versionCheckedAt=now,
					version="postgres-snapshot",
					props=props,
					source=_CATALOG_SOURCE_RECOVERY,
				)
			return filter_owner_quarantined_props(props)
		except Exception:
			logging.exception("Durable prop catalog snapshot was invalid")
	return filter_owner_quarantined_props(
		_rebuild_prop_catalog_from_local(fallback_version=shared_version)
	)


def _catalog_feed_state() -> dict[str, object]:
	"""Describe which layer served the props a caller is holding.

	A degraded feed is only honest if the client can see it. Callers get the
	source rather than a bare boolean so a shared-cache read is not conflated
	with a durable-snapshot recovery: one is normal multi-instance operation,
	the other means the live catalog could not be reached at all.
	"""

	with _prop_catalog_lock:
		source = str(_prop_catalog.get("source") or _CATALOG_SOURCE_EMPTY)
	return {
		"source": source,
		"recovery": source in _RECOVERY_SOURCES,
	}


def _record_line_movements_background(props: list[PropResponse]) -> None:
	try:
		result = record_line_movements(props)
		if result.get("recorded"):
			logging.info(
				"Recorded %s line movements of %s pregame prices",
				result["recorded"],
				result["considered"],
			)
	except Exception:
		logging.exception("Line movement capture thread failed")


def _rebuild_prop_catalog_from_local(
	*, fallback_version: object = None,
	persist_snapshot: bool = True,
) -> list[PropResponse]:
	"""Recompute props from this instance's local cache and republish.

	This is the only path that reflects data this instance just synced --
	the Redis/durable-snapshot layers can otherwise mask a fresh sync with
	an older cached value written by a different instance or an earlier run.
	"""
	now = time.monotonic()
	props = get_props()
	# Stamped once, here, where the catalog is assembled. Every reader of a
	# published catalog then sees the same grouping without recomputing it,
	# and a client cannot invent a different one.
	assign_prop_groups(props)
	with _prop_catalog_lock:
		_prop_catalog.update(
			loadedAt=now,
			versionCheckedAt=now,
			version=fallback_version,
			props=props,
			source=(
				_CATALOG_SOURCE_LIVE if props else _CATALOG_SOURCE_EMPTY
			),
		)
	if props:
		catalog_version = (
			f"{APP_VERSION}:"
			f"{max((prop.lastUpdatedUtc for prop in props), default='')}:"
			f"{len(props)}"
		)
		catalog_published = set_distributed_compressed_catalog(
			_PROP_CATALOG_COMPRESSED_KEY,
			props,
			ttl_seconds=86400,
			encode_item=lambda prop: prop.model_dump(mode="json"),
		)
		if not catalog_published:
			raise RuntimeError(
				"Fresh prop catalog could not be published to Redis: "
				+ (
					distributed_cache_last_write_error(
						_PROP_CATALOG_COMPRESSED_KEY
					)
					or "cause not reported by the cache client"
				)
			)
		# The uncompressed predecessor must not linger beside the payload
		# that replaced it; leaving it costs the exact memory this change
		# reclaims, and it would go stale the moment v2 is republished.
		delete_distributed_cache(_PROP_CATALOG_KEY)
		set_distributed_json(
			_PROP_CATALOG_VERSION_KEY,
			catalog_version,
			ttl_seconds=86400,
		)
		summary_published = _publish_prop_catalog_summary(
			props,
			catalog_published_at=datetime.now(timezone.utc).isoformat(),
		)
		if not summary_published:
			raise RuntimeError(
				"Fresh prop catalog summary could not be published to Redis: "
				+ (
					distributed_cache_last_write_error(
						_PROP_CATALOG_SUMMARY_KEY
					)
					or "cause not reported by the cache client"
				)
			)
		with _prop_catalog_lock:
			_prop_catalog["version"] = catalog_version
		# The durable snapshot was previously written only by the worker job
		# and by the branch that reads the catalog back out of Redis. Both
		# require Redis, so when it was unavailable nothing persisted a
		# snapshot at all: this instance would sync fresh props, hold them in
		# memory, publish nothing durable, and fall back to a snapshot hours
		# old the next time it restarted. This is the path with genuinely
		# fresh data, so it persists too, off the request thread because a
		# live request must never block on a Postgres write.
		if persist_snapshot:
			Thread(
				target=_persist_catalog_snapshot_background,
				args=(props,),
				daemon=True,
			).start()
			# Closing line value could not be computed at all: the table it
			# reads was empty, because the pipeline that filled it is
			# triggered from a test and from nowhere in production. The live
			# sync already holds every book's price, so recording movement
			# here costs no provider call. Off the request thread for the
			# same reason the durable snapshot is.
			Thread(
				target=_record_line_movements_background,
				args=(props,),
				daemon=True,
			).start()
	return props


def _prop_catalog_summary(
	props: list[PropResponse],
	*,
	catalog_published_at: str | None = None,
) -> dict[str, object]:
	return {
		"count": len(props),
		"lastDataUpdatedAt": max(
			(str(prop.lastUpdatedUtc or "") for prop in props),
			default="",
		) or None,
		"catalogPublishedAt": catalog_published_at,
		"version": APP_VERSION,
	}


def _prop_catalog_summary_from_version(
	value: object,
) -> dict[str, object] | None:
	if not isinstance(value, str):
		return None
	try:
		version_and_timestamp, raw_count = value.rsplit(":", 1)
		_version, last_data_updated_at = version_and_timestamp.split(":", 1)
		count = int(raw_count)
	except (ValueError, TypeError):
		return None
	if count <= 0:
		return None
	return {
		"count": count,
		"lastDataUpdatedAt": last_data_updated_at or None,
		"version": APP_VERSION,
	}


def _publish_prop_catalog_summary(
	props: list[PropResponse],
	*,
	catalog_published_at: str | None = None,
) -> bool:
	if not props:
		return False
	if catalog_published_at is None:
		existing = get_distributed_json(_PROP_CATALOG_SUMMARY_KEY)
		if isinstance(existing, dict):
			catalog_published_at = str(
				existing.get("catalogPublishedAt") or ""
			) or None
		# API instances also hydrate the shared catalog during rolling deploys.
		# Previously, an instance racing the worker could read the catalog before
		# its compact summary existed and then overwrite the worker's publication
		# receipt with null. A successfully hydrated non-empty shared catalog is
		# publicly available at this point, so it is safe—and required for an
		# auditable readiness signal—to stamp that publication here.
		if catalog_published_at is None:
			catalog_published_at = datetime.now(timezone.utc).isoformat()
	return set_distributed_json(
		_PROP_CATALOG_SUMMARY_KEY,
		_prop_catalog_summary(
			props,
			catalog_published_at=catalog_published_at,
		),
		ttl_seconds=86400,
	)


def _invalidate_prop_catalog(*, delete_shared: bool = True) -> None:
	with _prop_catalog_lock:
		_prop_catalog.update(
			loadedAt=0.0,
			versionCheckedAt=0.0,
			version=None,
			props=[],
			source=_CATALOG_SOURCE_EMPTY,
		)
	if delete_shared:
		delete_distributed_cache(_PROP_CATALOG_COMPRESSED_KEY)
		delete_distributed_cache(_PROP_CATALOG_KEY)
		delete_distributed_cache(_PROP_CATALOG_VERSION_KEY)
		delete_distributed_cache(_PROP_CATALOG_SUMMARY_KEY)


def _refresh_prop_catalog_now(
	*, persist_snapshot: bool = True,
) -> list[PropResponse]:
	"""Invalidate and immediately rebuild+republish the shared catalog.

	Render runs multiple API instances with separate local disks. Deleting
	the shared cache alone leaves a window where a *different* instance's
	next request falls back to its own (unsynced) local data instead of the
	fresh result this instance just produced. Rebuilding directly from local
	data (rather than through _cached_prop_catalog's normal fallback chain)
	matters here specifically: that chain checks the durable Postgres
	snapshot before ever recomputing, which would just hand back whatever
	stale snapshot was last written instead of the sync that just completed.
	"""
	# Keep the previous catalog until the streaming publisher atomically
	# renames the complete replacement into place.
	_invalidate_prop_catalog(delete_shared=False)
	props = _rebuild_prop_catalog_from_local(
		persist_snapshot=persist_snapshot,
	)
	for alert in evaluate_injury_impact_changes(props):
		realtime_hub.broadcast_from_thread(
			{
				"type": "injury.impact.changed",
				"version": 1,
				"eventId": alert["eventId"],
				"occurredAt": alert["occurredAt"],
				"data": alert,
			},
			"alerts",
		)
	return props


def _refresh_prop_catalog_resilient(
	*, persist_snapshot: bool = True, attempts: int = 3,
) -> list[PropResponse]:
	"""Publish a non-empty replacement catalog or fail the sync visibly.

	The provider lanes can finish successfully while the Redis promotion fails
	transiently.  Swallowing that failure leaves the API serving yesterday's
	catalog, which is then removed by the past-event filter and presents an
	empty board.  Retry the atomic publication and never call an empty catalog a
	success; the previous shared catalog remains untouched until rename.
	"""
	maximum_attempts = max(1, attempts)
	last_error: Exception | None = None
	for attempt in range(1, maximum_attempts + 1):
		try:
			props = _refresh_prop_catalog_now(
				persist_snapshot=persist_snapshot,
			)
			if not props:
				raise RuntimeError(
					"Fresh prop catalog rebuild returned no inventory"
				)
			return props
		except Exception as exc:
			last_error = exc
			logging.exception(
				"Fresh prop catalog publication failed attempt=%s/%s",
				attempt,
				maximum_attempts,
			)
			if attempt < maximum_attempts:
				time.sleep(min(2 ** (attempt - 1), 4))
	raise RuntimeError(
		"Fresh prop catalog could not be published after "
		f"{maximum_attempts} attempts: {last_error}"
	) from last_error

_sync_run_lock = Lock()
_sync_state_lock = Lock()
_SYNC_STATE_CACHE_KEY = "sync:global:state:v2"
_SYNC_STATE_CACHE_TTL_SECONDS = 60 * 60 * 24
_COVERAGE_STALL_SECONDS = max(
	300, int(os.getenv("PROP_COVERAGE_STALL_SECONDS", "900"))
)
_POST_PROCESSING_STALL_SECONDS = max(
	300, int(os.getenv("PROP_POST_PROCESSING_STALL_SECONDS", "900"))
)
_SYNC_JOB_STALL_SECONDS = min(
	180,
	max(120, int(os.getenv("PROP_SYNC_JOB_STALL_SECONDS", "180"))),
)
_SYNC_JOB_HEARTBEAT_SECONDS = 30
_sync_state: dict[str, object] = {
	"status": "idle",
	"startedAt": None,
	"finishedAt": None,
	"results": [],
	"error": None,
	"queuedJobId": None,
	"jobHeartbeatAt": None,
	"syncLockActive": False,
	"syncLockHealthy": None,
	"cooldownSeconds": LIVE_ODDS_SYNC_MIN_SECONDS,
	"nextAllowedAt": None,
	"fastLaneCompletedAt": None,
	"fastLaneResults": [],
	"coverageStatus": "idle",
	"coverageCompletedAt": None,
	"coverageResults": [],
	"coverageError": None,
	"coverageProgress": None,
	"coverageLastProgressAt": None,
	"sportsGameOddsStatus": "idle",
	"sportsGameOddsStartedAt": None,
	"sportsGameOddsCompletedAt": None,
	"sportsGameOddsResult": None,
	"sportsGameOddsError": None,
	"postProcessingStatus": "idle",
	"postProcessingStartedAt": None,
	"postProcessingStep": None,
	"postProcessingUpdatedAt": None,
	"postProcessingCompletedAt": None,
	"postProcessingDurationSeconds": None,
	"postProcessingError": None,
	"catalogPublicationStatus": "idle",
	"catalogPublicationAt": None,
	"catalogPublicationError": None,
	"lastFullCycleCompletedAt": None,
	"lastFullCycleDurationSeconds": None,
	"lastFullCycleJobId": None,
}


def _set_sync_state(**changes: object) -> None:
	with _sync_state_lock:
		_sync_state.update(changes)
		snapshot = dict(_sync_state)
	set_distributed_json(
		_SYNC_STATE_CACHE_KEY,
		snapshot,
		ttl_seconds=_SYNC_STATE_CACHE_TTL_SECONDS,
	)


def _sync_state_snapshot() -> dict[str, object]:
	shared = get_distributed_json(_SYNC_STATE_CACHE_KEY)
	with _sync_state_lock:
		local = dict(_sync_state)
		if isinstance(shared, dict):
			shared_started = str(shared.get("startedAt") or "")
			local_started = str(local.get("startedAt") or "")
			if shared_started >= local_started:
				local.update(shared)
				_sync_state.update(shared)
	if local.get("coverageStatus") == "running":
		last_progress = (
			local.get("coverageLastProgressAt")
			or local.get("fastLaneCompletedAt")
			or local.get("startedAt")
		)
		stall_seconds = 0
		if last_progress:
			try:
				parsed = datetime.fromisoformat(
					str(last_progress).replace("Z", "+00:00")
				)
				if parsed.tzinfo is None:
					parsed = parsed.replace(tzinfo=timezone.utc)
				stall_seconds = max(
					0,
					int((datetime.now(timezone.utc) - parsed).total_seconds()),
				)
			except ValueError:
				stall_seconds = 0
		local["coverageStallSeconds"] = stall_seconds
		local["coverageStalled"] = stall_seconds >= _COVERAGE_STALL_SECONDS
	else:
		local["coverageStallSeconds"] = 0
		local["coverageStalled"] = False
	if local.get("postProcessingStatus") == "running":
		last_update = (
			local.get("postProcessingUpdatedAt")
			or local.get("sportsGameOddsCompletedAt")
			or local.get("startedAt")
		)
		stall_seconds = 0
		if last_update:
			try:
				parsed = datetime.fromisoformat(
					str(last_update).replace("Z", "+00:00")
				)
				if parsed.tzinfo is None:
					parsed = parsed.replace(tzinfo=timezone.utc)
				stall_seconds = max(
					0,
					int((datetime.now(timezone.utc) - parsed).total_seconds()),
				)
			except ValueError:
				stall_seconds = 0
		local["postProcessingStallSeconds"] = stall_seconds
		local["postProcessingStalled"] = (
			stall_seconds >= _POST_PROCESSING_STALL_SECONDS
		)
	else:
		local["postProcessingStallSeconds"] = 0
		local["postProcessingStalled"] = False
	return local


def _sync_is_fresh(now: datetime | None = None) -> bool:
	current = now or datetime.now(timezone.utc)
	finished_raw = _sync_state_snapshot().get("finishedAt")
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


def _mark_sync_running(job_id: str | None = None) -> None:
	now = datetime.now(timezone.utc).isoformat()
	_set_sync_state(
		status="running", startedAt=now,
		finishedAt=None, results=[], error=None, queuedJobId=job_id,
		jobHeartbeatAt=now, syncLockActive=True, syncLockHealthy=True,
		nextAllowedAt=None,
		fastLaneCompletedAt=None, fastLaneResults=[],
		coverageStatus="pending", coverageCompletedAt=None,
		coverageResults=[], coverageError=None,
		coverageProgress=None, coverageLastProgressAt=None,
		sportsGameOddsStatus="pending", sportsGameOddsStartedAt=None,
		sportsGameOddsCompletedAt=None, sportsGameOddsResult=None,
		sportsGameOddsError=None,
		postProcessingStatus="pending", postProcessingStep=None,
		postProcessingStartedAt=None, postProcessingUpdatedAt=None,
		postProcessingCompletedAt=None, postProcessingDurationSeconds=None,
		postProcessingError=None,
		catalogPublicationStatus="pending", catalogPublicationAt=None,
		catalogPublicationError=None,
	)


def _run_sync_background(*, release_local_lock: bool = True) -> None:
	try:
		def mark_fast_lane_complete(results: list[dict[str, object]]) -> None:
			# Publish the first useful board quickly, but defer the expensive
			# durable snapshot until all providers are finished. Starting a
			# full serialization thread at every lane boundary retained several
			# complete catalogs at once and exhausted Render's 2 GB instance.
			try:
				_refresh_prop_catalog_resilient(persist_snapshot=False)
			except Exception as exc:
				_set_sync_state(
					catalogPublicationStatus="failed",
					catalogPublicationError=str(exc),
				)
				raise
			finished = datetime.now(timezone.utc)
			cooldown = _effective_sync_cooldown_seconds()
			_set_sync_state(
				# The board is already usable, but the cycle is not complete until
				# every provider and post-processing stage reaches a terminal state.
				status="running",
				finishedAt=None,
				cooldownSeconds=cooldown,
				nextAllowedAt=(finished + timedelta(seconds=cooldown)).isoformat(),
				fastLaneCompletedAt=finished.isoformat(),
				fastLaneResults=results,
				results=results,
				coverageStatus="running",
				coverageLastProgressAt=finished.isoformat(),
				catalogPublicationStatus="complete",
				catalogPublicationAt=finished.isoformat(),
				catalogPublicationError=None,
			)

		def mark_coverage_progress(progress: dict[str, object]) -> None:
			now = datetime.now(timezone.utc).isoformat()
			_set_sync_state(
				coverageStatus="running",
				coverageProgress=progress,
				coverageLastProgressAt=now,
			)

		def mark_coverage_complete(results: list[dict[str, object]]) -> None:
			finished = datetime.now(timezone.utc)
			_set_sync_state(
				coverageStatus="complete",
				coverageCompletedAt=finished.isoformat(),
				coverageResults=results,
				coverageError=None,
				results=results,
				sportsGameOddsStatus="pending",
			)

		def mark_sportsgameodds_started() -> None:
			_set_sync_state(
				sportsGameOddsStatus="running",
				sportsGameOddsStartedAt=datetime.now(timezone.utc).isoformat(),
				sportsGameOddsError=None,
			)

		post_processing_board: list[PropResponse] | None = None

		def mark_sportsgameodds_complete(
			result: dict[str, object],
		) -> list[PropResponse]:
			nonlocal post_processing_board
			post_started = datetime.now(timezone.utc)
			partial = bool(
				result.get("error")
				or result.get("partial")
				or result.get("failedLeagues")
			)
			_set_sync_state(
				sportsGameOddsStatus="partial" if partial else "complete",
				sportsGameOddsCompletedAt=datetime.now(timezone.utc).isoformat(),
				sportsGameOddsResult=result,
				sportsGameOddsError=(
					str(result.get("error") or "Some leagues were unavailable")
					if partial else None
				),
				postProcessingStatus="running",
				postProcessingStartedAt=post_started.isoformat(),
				postProcessingStep="catalog_refresh",
				postProcessingUpdatedAt=post_started.isoformat(),
			)
			# One final rebuild includes coverage and SportsGameOdds, and is the
			# only refresh in this run that starts a durable snapshot write.
			try:
				post_processing_board = _refresh_prop_catalog_resilient(
					persist_snapshot=True,
				)
			except Exception as exc:
				_set_sync_state(
					catalogPublicationStatus="failed",
					catalogPublicationError=str(exc),
				)
				raise
			_set_sync_state(
				catalogPublicationStatus="complete",
				catalogPublicationAt=datetime.now(timezone.utc).isoformat(),
				catalogPublicationError=None,
			)
			return post_processing_board

		def mark_post_processing_progress(step: str) -> None:
			_set_sync_state(
				postProcessingStatus="running",
				postProcessingStep=step,
				postProcessingUpdatedAt=datetime.now(timezone.utc).isoformat(),
			)

		results = run_global_sync_pipeline(
			mark_fast_lane_complete,
			mark_coverage_complete,
			mark_coverage_progress,
			mark_sportsgameodds_started,
			mark_sportsgameodds_complete,
			mark_post_processing_progress,
		)
		_set_sync_state(
			postProcessingStatus="running",
			postProcessingStep="closing_line_capture",
			postProcessingUpdatedAt=datetime.now(timezone.utc).isoformat(),
		)
		# Reuse the catalog that this same cycle already built and published.
		# A second get_props() here repeated history/projection hydration after
		# board_projection had just consumed the identical objects.
		closing_line_board = (
			post_processing_board
			if post_processing_board is not None
			else _cached_prop_catalog()
		)
		clv_capture = capture_closing_lines_from_props(closing_line_board)
		quota = quota_snapshot()
		finished = datetime.now(timezone.utc)
		state = _sync_state_snapshot()
		post_started_raw = state.get("postProcessingStartedAt")
		post_duration: int | None = None
		if post_started_raw:
			try:
				post_started = datetime.fromisoformat(
					str(post_started_raw).replace("Z", "+00:00")
				)
				if post_started.tzinfo is None:
					post_started = post_started.replace(tzinfo=timezone.utc)
				post_duration = max(
					0, int((finished - post_started).total_seconds())
				)
			except ValueError:
				post_duration = None
		started_raw = state.get("startedAt")
		cycle_duration: int | None = None
		if started_raw:
			try:
				cycle_started = datetime.fromisoformat(
					str(started_raw).replace("Z", "+00:00")
				)
				if cycle_started.tzinfo is None:
					cycle_started = cycle_started.replace(tzinfo=timezone.utc)
				cycle_duration = max(
					0, int((finished - cycle_started).total_seconds())
				)
			except ValueError:
				cycle_duration = None
		cooldown = _effective_sync_cooldown_seconds()
		_set_sync_state(
			status="complete",
			finishedAt=finished.isoformat(),
			cooldownSeconds=cooldown,
			nextAllowedAt=(finished + timedelta(seconds=cooldown)).isoformat(),
			results=results,
			clvCapture=clv_capture,
			providerQuota=quota,
			postProcessingStatus="complete",
			postProcessingStep="complete",
			postProcessingUpdatedAt=finished.isoformat(),
			postProcessingCompletedAt=finished.isoformat(),
			postProcessingDurationSeconds=post_duration,
			postProcessingError=None,
			lastFullCycleCompletedAt=finished.isoformat(),
			lastFullCycleDurationSeconds=cycle_duration,
			lastFullCycleJobId=state.get("queuedJobId"),
			error=None,
		)
	except Exception as exc:
		logging.exception("Background prop sync failed")
		state = _sync_state_snapshot()
		primary_complete = bool(state.get("fastLaneCompletedAt"))
		coverage_complete = bool(state.get("coverageCompletedAt"))
		provider_complete = bool(state.get("sportsGameOddsCompletedAt"))
		_set_sync_state(
			status="complete" if primary_complete else "failed",
			finishedAt=datetime.now(timezone.utc).isoformat(),
			coverageStatus=(
				"complete" if coverage_complete
				else "failed" if primary_complete
				else "not_started"
			),
			coverageError=(
				None if coverage_complete or not primary_complete else str(exc)
			),
			sportsGameOddsStatus=(
				str(state.get("sportsGameOddsStatus")) if provider_complete
				else "failed" if coverage_complete
				else "not_started"
			),
			sportsGameOddsError=(
				state.get("sportsGameOddsError") if provider_complete
				else str(exc) if coverage_complete else None
			),
			postProcessingStatus="failed" if provider_complete else "not_started",
			postProcessingStep="failed" if provider_complete else None,
			postProcessingUpdatedAt=datetime.now(timezone.utc).isoformat(),
			postProcessingError=str(exc) if provider_complete else None,
			error=None if primary_complete else str(exc),
		)
	finally:
		if release_local_lock and _sync_run_lock.locked():
			_sync_run_lock.release()


def run_queued_prop_sync(job_id: str | None = None) -> None:
	"""RQ worker entrypoint; retries are managed by the durable queue."""
	lock_token = acquire_global_sync_lock()
	if lock_token is None:
		logging.info("Skipping duplicate queued prop sync; another run is active")
		return
	heartbeat_stop = Event()
	heartbeat_thread: Thread | None = None
	try:
		_mark_sync_running(job_id)

		def maintain_sync_lease() -> None:
			while not heartbeat_stop.wait(_SYNC_JOB_HEARTBEAT_SECONDS):
				now = datetime.now(timezone.utc).isoformat()
				lock_healthy = refresh_global_sync_lock(lock_token)
				_set_sync_state(
					queuedJobId=job_id,
					jobHeartbeatAt=now,
					syncLockHealthy=lock_healthy,
				)
				if not lock_healthy:
					logging.error(
						"Queued prop sync lost its distributed lock job_id=%s",
						job_id,
					)

		heartbeat_thread = Thread(
			target=maintain_sync_lease,
			name="prop-sync-heartbeat",
			daemon=True,
		)
		heartbeat_thread.start()
		_run_sync_background(release_local_lock=False)
	finally:
		heartbeat_stop.set()
		if heartbeat_thread is not None:
			heartbeat_thread.join(timeout=2)
		_set_sync_state(
			jobHeartbeatAt=datetime.now(timezone.utc).isoformat(),
			syncLockActive=False,
		)
		release_global_sync_lock(lock_token)


def _reconcile_catalog_snapshot() -> bool:
	"""Record the props this instance is serving if they are newer.

	Fresh props in memory do not imply a fresh snapshot on disk. The
	durable write only ever happened as a side effect of the worker job
	or of reading the catalog back out of Redis, so an instance could
	serve current props for hours while the snapshot it would restore
	from stayed hours behind -- which is exactly what a restart then
	exposed.
	"""

	try:
		props = get_props()
		if not props:
			return False
		if not snapshot_is_behind(props):
			return False
		rows = [prop.model_dump(mode='json') for prop in props]
		return save_catalog_snapshot(rows)
	except Exception:
		logging.exception("Catalog snapshot reconciliation failed")
		return False


async def _ensure_props_available() -> None:
	"""Check startup freshness without running provider work in the API."""
	props = await asyncio.to_thread(get_props)
	if not _prop_cache_needs_refresh(props):
		logging.info("Startup prop check ready props=%s", len(props))
		# Returning here without this left the durable snapshot untouched
		# whenever the local cache happened to be fresh, which is the
		# common case and the reason it could rot for hours.
		await asyncio.to_thread(_reconcile_catalog_snapshot)
		return
	queued = _enqueue_prop_refresh()
	queue_state = await asyncio.to_thread(job_queue_health)
	if int(queue_state.get("workers") or 0) < 1:
		logging.error(
			"No RQ worker is active; preserving the durable catalog instead of "
			"running a memory-intensive provider sync in the API process"
		)
		return
	if queued is None:
		logging.warning(
			"Startup prop cache is empty or stale; worker refresh is already "
			"queued or unavailable props=%s",
			len(props),
		)
	else:
		logging.warning(
			"Startup prop cache is empty or stale; queued worker refresh "
			"job=%s props=%s",
			queued.get("id"),
			len(props),
		)


def _prop_cache_needs_refresh(
	props: list[PropResponse],
	now_utc: datetime | None = None,
) -> bool:
	if not props:
		return True
	latest = max(
		(str(getattr(prop, "lastUpdatedUtc", "") or "") for prop in props),
		default="",
	)
	# Deliberately NOT PROP_FEED_STALE_MINUTES. That knob answers "when should
	# the feed be reported unhealthy" and production sets it to 180; reusing it
	# here silently meant the watchdog let the feed sit three hours old before
	# queueing a refresh, which is why deploy smoke checks kept failing on
	# staleness. When to refresh and when to alarm are separate decisions.
	refresh_after_minutes = max(
		5,
		int(os.getenv("PROP_FEED_REFRESH_AFTER_MINUTES", "30")),
	)
	return _is_stale_timestamp(
		latest,
		now_utc or datetime.now(timezone.utc),
		refresh_after_minutes,
	)


async def _maintain_prop_freshness() -> None:
	"""Queue provider refreshes without making the web process perform I/O."""
	check_seconds = max(
		60,
		int(os.getenv("PROP_FEED_WATCHDOG_SECONDS", "300")),
	)
	while True:
		await asyncio.sleep(check_seconds)
		try:
			props = await asyncio.to_thread(get_props)
			# Runs whether or not a refresh is due, so a snapshot that has
			# fallen behind is repaired without waiting for a restart.
			await asyncio.to_thread(_reconcile_catalog_snapshot)
			if not _prop_cache_needs_refresh(props):
				continue
			queued = _enqueue_prop_refresh()
			if queued is None:
				logging.warning(
					"Prop freshness refresh was not queued; preserving cached props"
				)
			else:
				logging.info(
					"Prop freshness refresh queued job=%s props=%s",
					queued.get("id"),
					len(props),
				)
		except asyncio.CancelledError:
			raise
		except Exception:
			logging.exception("Prop freshness watchdog check failed")


def _sync_has_active_work(state: dict[str, object]) -> bool:
	return (
		str(state.get("status") or "").lower() in {"queued", "running"}
		or any(
			str(state.get(key) or "").lower() in {"pending", "running"}
			for key in (
				"coverageStatus",
				"sportsGameOddsStatus",
				"postProcessingStatus",
			)
		)
	)


def _enqueue_prop_refresh() -> dict[str, object] | None:
	"""Deduplicate recovery work across API restarts and watchdog checks."""
	state = _sync_state_snapshot()
	if _sync_has_active_work(state):
		# Reuse the exact-job and heartbeat checks used by explicit refreshes.
		# A rolling worker deploy can otherwise leave shared state marked running
		# forever after the original RQ job has disappeared.
		return _enqueue_requested_prop_sync()
	# One recovery job per 15-minute window is enough. RQ handles retries and
	# the worker owns all provider/network work; the web service stays responsive.
	bucket = int(time.time() // 900)
	return enqueue_background_job(
		"jobs.run_prop_sync",
		job_id=f"prop-freshness:{APP_VERSION[:12]}:{bucket}",
	)


def _enqueue_requested_prop_sync() -> dict[str, object] | None:
	"""Queue an explicit refresh while deduplicating an active shared run."""
	state = _sync_state_snapshot()
	status = str(state.get("status") or "").lower()
	downstream_active = _sync_has_active_work(state)
	if status in {"queued", "running"} or downstream_active:
		job_id = str(state.get("queuedJobId") or "").strip() or None
		started_at = state.get("startedAt")
		age_seconds: float | None = None
		if started_at:
			try:
				parsed = datetime.fromisoformat(
					str(started_at).replace("Z", "+00:00")
				)
				if parsed.tzinfo is None:
					parsed = parsed.replace(tzinfo=timezone.utc)
				age_seconds = (
					datetime.now(timezone.utc) - parsed
				).total_seconds()
			except ValueError:
				age_seconds = None
		heartbeat_age: float | None = None
		heartbeat_at = state.get("jobHeartbeatAt")
		if heartbeat_at:
			try:
				parsed = datetime.fromisoformat(
					str(heartbeat_at).replace("Z", "+00:00")
				)
				if parsed.tzinfo is None:
					parsed = parsed.replace(tzinfo=timezone.utc)
				heartbeat_age = (
					datetime.now(timezone.utc) - parsed
				).total_seconds()
			except ValueError:
				heartbeat_age = None
		job = (
			background_job_status(job_id)
			if (age_seconds or 0) >= 60 and job_id
			else {}
		)
		exact_status = str(job.get("status") or "").lower()
		active_statuses = {"queued", "started", "deferred", "scheduled"}
		stalled = (
			(status == "running" or downstream_active)
			and (heartbeat_age if heartbeat_age is not None else age_seconds or 0)
			>= _SYNC_JOB_STALL_SECONDS
		)
		job_missing = bool(job) and job.get("available") is True and not job.get("found")
		job_inactive = bool(job) and job.get("found") is True and exact_status not in active_statuses
		orphaned = bool(
			age_seconds is not None
			and age_seconds >= 60
			and (not job_id or job_missing or job_inactive or stalled)
		)
		if not orphaned:
			return {
				"id": str(job_id or "active-prop-sync"),
				"status": "running" if downstream_active else status,
				"deduplicated": True,
			}
		logging.warning(
			"Recovering orphaned sync state status=%s job_id=%s "
			"job_status=%s age_seconds=%s heartbeat_age=%s",
			status,
			job_id,
			exact_status or "missing",
			int(age_seconds),
			int(heartbeat_age) if heartbeat_age is not None else None,
		)
	bucket = int(time.time() // 120)
	queued = enqueue_background_job(
		"jobs.run_prop_sync",
		job_id=f"prop-request:{APP_VERSION[:12]}:{bucket}",
	)
	if queued is not None:
		_set_sync_state(
			status="queued",
			startedAt=datetime.now(timezone.utc).isoformat(),
			finishedAt=None,
			error=None,
			queuedJobId=queued.get("id"),
			jobHeartbeatAt=None,
			syncLockActive=False,
			syncLockHealthy=None,
			coverageStatus="pending",
			sportsGameOddsStatus="pending",
			postProcessingStatus="pending",
		)
	return queued


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
	"EPL": "soccer/eng.1",
	"MLS": "soccer/usa.1",
	"UFC": "mma/ufc",
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
			# A slow or unsupported league must not hold the full multi-sport
			# board hostage. Other leagues load in parallel and provider
			# fallbacks remain available.
			timeout=min(4, HTTP_TIMEOUT_SECONDS),
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
	# Reuse the Redis-backed prop catalog. Re-reading and rebuilding thousands
	# of PropResponse rows made every scoreboard request pay the prop-feed cost.
	prop_list = _cached_prop_catalog()
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
	if league == "MLB" and not espn_games:
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

	# ESPN already supplies scheduled times, scores, and live/final state in a
	# single request. When it has the slate, avoid two additional provider
	# round-trips (events + scores) for every sport.
	if espn_games:
		return [
			_normalize_scoreboard_game(
				event,
				league,
				now,
				live_detail_map=live_detail_map,
				shared_time_map=shared_time_map,
			)
			for event in espn_games
			if _event_on_date(event, target_date=target_date)
		]

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


def _scoreboard_dedupe_key(game: dict[str, object]) -> str:
	"""Preserve doubleheaders while still collapsing duplicate provider rows."""
	event_id = str(
		game.get("id")
		or game.get("gameId")
		or game.get("eventId")
		or ""
	).strip()
	if event_id:
		return f"id:{event_id}"
	return "|".join((
		str(game.get("league", "")).strip(),
		str(game.get("away_team", "")).strip(),
		str(game.get("home_team", "")).strip(),
		str(
			game.get("startTimeUtc")
			or game.get("start_time")
			or ""
		).strip(),
	))


def _active_ticket_team(leg: object) -> str:
	if not isinstance(leg, dict):
		return ""
	team_value = leg.get("team") or leg.get("team_key") or ""
	return str(team_value).strip().upper()


def _grade_active_ticket_leg(
	*,
	side: str,
	current: float | None,
	line: float,
	game_status: str,
) -> str:
	if current is None:
		return "live"
	normalized_side = str(side).strip().lower()
	is_final = str(game_status).strip().lower() == "final"
	# Overs that have cleared their line and unders that have exceeded it
	# are irreversible, so surface the outcome immediately. Other outcomes
	# remain live until the authoritative final snapshot arrives.
	if not is_final:
		if normalized_side == "over" and current > line:
			return "win"
		if normalized_side == "under" and current > line:
			return "loss"
		return "live"
	if current == line:
		return "push"
	if normalized_side == "over":
		return "win" if current > line else "loss"
	if normalized_side == "under":
		return "win" if current < line else "loss"
	return "live"


def _graded_slip_legs(slip: SlipResponse, *, season: str) -> list[dict[str, object]]:
	legs: list[dict[str, object]] = []
	for leg in slip.legs:
		snapshot = get_live_player_stat_snapshot(
			player_name=leg.player,
			team="",
			prop_type=leg.market,
			sport=leg.sport,
			season=season,
			event_id=leg.event_id,
			matchup=leg.matchup,
			game_start_time=leg.game_start_time,
		)
		current_value = snapshot.value
		snapshot_status = snapshot.status.strip().lower()
		game_status = (
			"Final"
			if leg.game_completed or snapshot.completed
			else "Live"
			if snapshot_status in {"live", "in_progress", "inprogress", "ongoing"}
			or str(leg.game_status).strip().lower() == "live"
			else "Scheduled"
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
				"live_stat_status": snapshot.status,
				"game_detail": snapshot.game_detail,
				"odds": leg.odds,
			}
		)
	return legs


def _active_ticket_payload(*, season: str, user_id: str) -> dict[str, object]:
	active_slips = get_slips("active", user_id=user_id)
	if not active_slips:
		return {
			"slip_title": "Active Slip",
			"payout": "$0.00",
			"legs": [],
		}

	slip = active_slips[0]
	legs = _graded_slip_legs(slip, season=season)

	return {
		"slip_id": slip.id,
		"slip_title": f"{len(slip.legs)}-Pick Active Ticket",
		"status": slip.status,
		"payout": f"${slip.potential_payout:.2f}",
		"created_at": slip.created_at,
		"legs": legs,
	}


def _live_slip_stats_payload(*, season: str, user_id: str) -> dict[str, object]:
	"""Live current-stat values for every active slip's legs, keyed by
	slip id. Powers Slip Watcher's PrizePicks-style progress bars for all
	locked slips, not just the first one."""
	active_slips = get_slips("active", user_id=user_id)
	slips: dict[str, object] = {}
	for slip in active_slips:
		slips[slip.id] = {
			"slip_title": f"{len(slip.legs)}-Pick Ticket",
			"status": slip.status,
			"legs": _graded_slip_legs(slip, season=season),
		}
	return {"slips": slips}


@app.get("/health")
def health() -> dict[str, object]:
	return {
		"status": "ok",
		"service": "prop-intelligence-api",
		"version": APP_VERSION,
		"providers": {
			"sportradarMultiSportConfigured": bool(SPORTRADAR_API_KEY),
			"sportradarWnbaConfigured": bool(SPORTRADAR_WNBA_API_KEY),
			"ballDontLieConfigured": bool(BALLDONTLIE_API_KEY),
		},
	}


@app.get("/ready")
def ready(response: Response) -> dict[str, object]:
	result = runtime_readiness()
	if not result["ready"]:
		response.status_code = 503
	return {"version": APP_VERSION, **result}


@app.get("/api/market-intelligence")
def market_intelligence(
	sport: str | None = Query(default=None),
	limit: int = Query(default=250, ge=1, le=1000),
) -> dict[str, object]:
	rows = latest_market_intelligence(
		sport=sport.strip() if sport else None,
		limit=limit,
	)
	return {"count": len(rows), "items": rows}


def _job_queue_summary() -> dict[str, object]:
	"""Queue reachability and worker count, without leaking connection details."""

	try:
		state = job_queue_health()
	except Exception as exc:
		return {"available": False, "error": type(exc).__name__}
	if not isinstance(state, dict):
		return {"available": False, "error": "unexpected_response"}
	return {
		"configured": bool(state.get("configured")),
		"available": bool(state.get("available")),
		"mode": state.get("mode"),
		"workers": state.get("workers"),
		"queued": state.get("queued"),
		"started": state.get("started"),
		"failed": state.get("failed"),
		"retryPolicy": state.get("retryPolicy"),
	}


@app.get("/api/operations/projection-grade")
def projection_grade(
	sport: str = Query(default="WNBA"),
	_membership: Membership = Depends(require_pro),
) -> dict[str, object]:
	"""Grade the projection against outcomes it has already seen.

	The live record is 409 graded picks, 408 of them in the tier nobody
	should bet, so it cannot say whether the model works. This replays the
	game logs already stored -- projecting each game from the games before
	it only -- and reports bias per market, which is what a projection built
	on the wrong statistic looks like.
	"""

	return grade_sport(sport.strip().upper() or "WNBA")


@app.get("/api/briefing/today")
def todays_briefing(
	_membership: Membership = Depends(require_pro),
) -> dict[str, object]:
	"""Today's board reduced to what a person needs before deciding anything."""

	coverage = sport_coverage()
	empty = [
		str(key).split("_")[-1].upper()
		for key in (coverage.get("fetchedButEmpty") or [])
	]
	now_utc = datetime.now(timezone.utc)
	local_timezone = _scoreboard_timezone()
	return build_briefing(
		_cached_prop_catalog(),
		empty_sports=empty,
		target_date=now_utc.astimezone(local_timezone).date(),
		local_timezone=local_timezone,
		now=now_utc,
		stale_after_minutes=max(
			5,
			int(os.getenv("PROP_FEED_STALE_MINUTES", "180")),
		),
	)


@app.get("/api/performance/track-record")
def public_performance_track_record(
	# Closed until the numbers are trusted.
	#
	# Served publicly for a few hours today and immediately published a
	# beat-the-close rate of 6.7% across 4,377 samples. Random selection beats
	# the close about half the time, so that is not a weak result, it is a
	# broken measurement -- and 408 of 409 graded picks landing in the BASELINE
	# tier says the snapshot probability is not the probability the board
	# shows. Publishing a record we cannot stand behind is wrong in both
	# directions: it misleads if it is wrong, and it costs sales if it is right.
	_membership: Membership = Depends(require_pro),
) -> dict[str, object]:
	"""The model's record, readable without an account.

	Every number here was already computed and already served -- behind
	require_pro, where only people who had subscribed could see it. A track
	record visible only to existing subscribers cannot do the one job a track
	record has, which is to let someone decide whether to become one.

	Aggregate results only. Nothing here exposes a projection, a line or a
	pick, so publishing it gives away the evidence without giving away the
	product.
	"""

	return public_track_record()


@app.get("/api/operations/prop-feed-health")
def prop_feed_health(response: Response) -> dict[str, object]:
	response.headers["Cache-Control"] = "private, no-store, max-age=0"
	with _prop_metrics_lock:
		metrics = dict(_prop_metrics)
	# Request counters are process-local, while the prop catalog is shared by
	# every API instance. A fresh deploy therefore starts with a zero count and
	# no timestamp even when Redis already holds a healthy catalog. Use that
	# fleet-wide summary as the source of truth for catalog health; keep the
	# local counters for request success/latency diagnostics below.
	shared_summary = get_distributed_json(_PROP_CATALOG_SUMMARY_KEY)
	if not isinstance(shared_summary, dict) or int(shared_summary.get("count") or 0) <= 0:
		shared_summary = _prop_catalog_summary_from_version(
			get_distributed_json(_PROP_CATALOG_VERSION_KEY)
		)
	if not isinstance(shared_summary, dict) or int(shared_summary.get("count") or 0) <= 0:
		try:
			shared_summary = _prop_catalog_summary(_cached_prop_catalog())
		except Exception as exc:
			logging.warning("Prop feed health catalog fallback failed error=%s", exc)
	if isinstance(shared_summary, dict) and int(shared_summary.get("count") or 0) > 0:
		metrics["lastTotalCount"] = int(shared_summary["count"])
		metrics["lastDataUpdatedAt"] = shared_summary.get("lastDataUpdatedAt")
	requests_count = max(1, int(metrics["requests"]))
	last_data_updated = str(metrics.get("lastDataUpdatedAt") or "")
	stale_after_minutes = max(
		5,
		int(os.getenv("PROP_FEED_STALE_MINUTES", "45")),
	)
	stale = _is_stale_timestamp(
		last_data_updated,
		datetime.now(timezone.utc),
		stale_after_minutes,
	)
	latest_empty = int(metrics.get("lastTotalCount") or 0) == 0
	feed_status = (
		"degraded"
		if metrics.get("lastRequestSucceeded") is False or latest_empty or stale
		else "ok"
	)
	queue_summary = _job_queue_summary()
	coverage_summary = sport_coverage()
	key_summary = active_key_snapshot()
	certification = sync_certification(
		feed={"latestEmpty": latest_empty, "stale": stale},
		queue=queue_summary,
		keys=key_summary,
		coverage=coverage_summary,
	)
	return {
		"status": feed_status,
		"version": APP_VERSION,
		"latestEmpty": latest_empty,
		"stale": stale,
		"staleAfterMinutes": stale_after_minutes,
		"successRate": round(
			(requests_count - int(metrics["errors"])) / requests_count,
			4,
		),
		# Whether the durable snapshot is actually being written. A stale
		# snapshot beside a healthy feed means this instance is serving
		# fresh props it has failed to record, which is otherwise
		# invisible from outside the process.
		"snapshotPersist": catalog_snapshot_status(),
		# Redis reachability and live worker count. Whether background
		# jobs can run at all was previously only visible on the
		# owner-authenticated control panel, which is no help when that
		# panel is the thing failing to load. Counts only, no connection
		# details.
		"jobQueue": queue_summary,
		# Whether a raised alert can actually reach anyone. Delivery
		# failures are swallowed so an alert cannot take a pipeline down,
		# which makes a misconfigured channel look exactly like a quiet
		# one -- and it did, for a day, while the configured URL answered
		# 405 because it was not a webhook endpoint. No URL is returned.
		"alertChannel": alert_channel_health(),
		# Which configured sports actually return props. An empty rail has
		# three very different causes and they are indistinguishable from
		# outside: out of season, not covered by the plan, or not requested.
		"sportCoverage": coverage_summary,
		# Which bookmakers the provider has actually returned, against those
		# requested. A key that is asked for and never seen is the difference
		# between a book with no props today and one the plan does not cover.
		"bookmakerCoverage": bookmaker_coverage(),
		# Which odds key is in use and how many are configured. A 401 from a
		# deactivated key is treated as quota exhaustion and rotates to the
		# next key one way, never back, until the process restarts -- so a
		# run can begin on a healthy key and end with none left while the
		# environment still looks correctly configured. Index and count
		# only; no key material.
		"oddsApiKeys": key_summary,
		"syncCertification": certification,
		# Whether the configured key can read historical odds. Status and
		# quota only -- the key itself is never returned or logged.
		"historicalOddsAccess": historical_access(),
		# Why the buyer-facing record last failed to build, if it did. That
		# page answers 200 with "unavailable" rather than erroring, which
		# would otherwise hide the cause completely.
		"trackRecordLastError": track_record_last_failure(),
		# Where the live board would draw hit_probability from if it were
		# snapshotted right now, and which tier each would land in.
		"snapshotProbability": _snapshot_probability_sources(),
		# What a price-aware threshold would call pickable, against the
		# single global one in use. Measurement only; decides nothing.
		"selectabilityProjection": _selectability_projection(),
		# How the projection did on games it had not seen, per market.
		# Bias is the number to read: a market built on the wrong
		# statistic is confidently wrong in one direction, not noisy.
		"projectionGrade": _projection_grade_snapshot(),
		**metrics,
	}


@app.get("/api/game-markets")
def game_markets(
	sport: str = Query(default="MLB"),
	refresh: bool = Query(default=False),
) -> dict[str, object]:
	try:
		return get_game_markets(sport, force=refresh)
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc)) from exc
	except (requests.RequestException, RuntimeError) as exc:
		logging.exception("Game markets provider request failed")
		raise HTTPException(
			status_code=503,
			detail="Game markets are temporarily unavailable.",
		) from exc


@app.get("/api/operations/game-market-health")
def game_market_feed_health() -> dict[str, object]:
	return {"version": APP_VERSION, **game_market_health()}


@app.get("/health/storage")
def storage_health() -> dict[str, object]:
	storage = slip_storage_health()
	if storage["status"] != "ok":
		raise HTTPException(status_code=503, detail=storage)
	return storage


@app.get("/health/providers")
def provider_health() -> dict[str, object]:
	quota = quota_snapshot()
	sync_state = _sync_state_snapshot()
	sportsgameodds = sportsgameodds_usage()
	sportsgameodds.update({
		"syncStatus": sync_state.get("sportsGameOddsStatus"),
		"syncStartedAt": sync_state.get("sportsGameOddsStartedAt"),
		"syncCompletedAt": sync_state.get("sportsGameOddsCompletedAt"),
		"latestSync": sync_state.get("sportsGameOddsResult"),
		"syncError": sync_state.get("sportsGameOddsError"),
	})
	return {
		"oddsApi": {
			"status": "low_quota" if quota["lowQuota"] else "ok",
			**quota,
		},
		"sportsGameOdds": sportsgameodds,
		"espnHeadshots": espn_headshot_cache_health(),
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
def prop_alerts(
	response: Response,
	_membership: Membership = Depends(require_pro),
) -> dict[str, object]:
	try:
		response.headers["Cache-Control"] = "private, no-store, max-age=0"
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


@app.get("/api/injury-alerts")
def injury_alerts(
	response: Response,
	limit: int = Query(default=50, ge=1, le=100),
	_membership: Membership = Depends(require_pro),
) -> dict[str, object]:
	response.headers["Cache-Control"] = "private, no-store, max-age=0"
	alerts = injury_alert_history(limit)
	return {"count": len(alerts), "alerts": alerts}
@app.get("/api/props/readiness")
def props_readiness(response: Response) -> dict[str, object]:
	"""Expose feed health without exposing proprietary prop rows.

	The serving layer is deliberately public. It carries no prop rows and no
	credentials -- strictly less than the inventory count and commit SHA
	already returned here -- and the unauthenticated deploy smoke test is a
	real consumer that gates production on this endpoint. The authenticated
	/api/props copy is what the board reads; this one exists so operators can
	see a degraded feed without holding a key.
	"""
	started_at = time.perf_counter()
	summary = get_distributed_json(_PROP_CATALOG_SUMMARY_KEY)
	if not isinstance(summary, dict) or int(summary.get("count") or 0) <= 0:
		summary = _prop_catalog_summary_from_version(
			get_distributed_json(_PROP_CATALOG_VERSION_KEY)
		)
	if isinstance(summary, dict) and int(summary.get("count") or 0) > 0:
		count = int(summary["count"])
		last_data_updated_at = str(
			summary.get("lastDataUpdatedAt") or ""
		)
		catalog_published_at = str(
			summary.get("catalogPublishedAt") or ""
		)
	else:
		prop_list = _cached_prop_catalog()
		fallback_summary = _prop_catalog_summary(prop_list)
		count = int(fallback_summary["count"])
		last_data_updated_at = str(
			fallback_summary.get("lastDataUpdatedAt") or ""
		)
		catalog_published_at = ""
	response.headers["Cache-Control"] = "private, no-store, max-age=0"
	return {
		"status": "ok" if count else "empty",
		"count": count,
		"lastDataUpdatedAt": last_data_updated_at or None,
		"catalogPublishedAt": catalog_published_at or None,
		"version": APP_VERSION,
		"responseMs": round((time.perf_counter() - started_at) * 1000),
		"dataProtected": True,
		**_catalog_feed_state(),
	}


def _provider_category_coverage(
	props: list[PropResponse],
	*,
	selected_site: str,
) -> dict[str, object]:
	"""Detect a partial selected-site payload against the same live events."""

	def site_key(value: object) -> str:
		normalized = str(value or "").strip().lower()
		normalized = normalized.replace(" ", "").replace("_", "").replace("-", "")
		if "betr" in normalized:
			return "betr"
		if "pick6" in normalized or "pick06" in normalized:
			return "pick6"
		return normalized

	site = site_key(selected_site)
	if not site or site == "all":
		return {"limited": False, "selectedSite": site, "issues": []}

	selected_events: dict[str, set[str]] = {}
	selected_counts: Counter[tuple[str, str]] = Counter()
	for prop in props:
		if site_key(getattr(prop, "sportsbook", "")) != site:
			continue
		sport = str(getattr(prop, "sport", "") or "").strip().upper()
		category = str(getattr(prop, "category", "") or "").strip().upper()
		event = str(
			getattr(prop, "eventId", "")
			or getattr(prop, "gameId", "")
			or getattr(prop, "apiSportsGameId", "")
			or getattr(prop, "matchup", "")
		).strip()
		if not sport or not category or not event:
			continue
		selected_events.setdefault(sport, set()).add(event)
		selected_counts[(sport, category)] += 1

	counts_by_site: dict[str, Counter[tuple[str, str]]] = {}
	for prop in props:
		book = site_key(getattr(prop, "sportsbook", ""))
		sport = str(getattr(prop, "sport", "") or "").strip().upper()
		category = str(getattr(prop, "category", "") or "").strip().upper()
		event = str(
			getattr(prop, "eventId", "")
			or getattr(prop, "gameId", "")
			or getattr(prop, "apiSportsGameId", "")
			or getattr(prop, "matchup", "")
		).strip()
		if (
			not book
			or not sport
			or not category
			or event not in selected_events.get(sport, set())
		):
			continue
		counts_by_site.setdefault(book, Counter())[(sport, category)] += 1

	issues: list[dict[str, object]] = []
	for (sport, category), selected_count in selected_counts.items():
		benchmark_site = ""
		benchmark_count = 0
		for book, counts in counts_by_site.items():
			if book == site:
				continue
			count = int(counts.get((sport, category), 0))
			if count > benchmark_count:
				benchmark_site = book
				benchmark_count = count
		if benchmark_count < 12 or selected_count * 2 > benchmark_count:
			continue
		issues.append({
			"sport": sport,
			"category": category,
			"selectedCount": selected_count,
			"benchmarkCount": benchmark_count,
			"benchmarkSite": benchmark_site.upper(),
			"coverageRatio": round(selected_count / benchmark_count, 3),
		})

	issues.sort(
		key=lambda issue: (
			float(issue["coverageRatio"]),
			-int(issue["benchmarkCount"]),
			str(issue["category"]),
		),
	)
	return {
		"limited": bool(issues),
		"selectedSite": site.upper(),
		"issues": issues[:5],
	}


@app.get("/api/props")
def props(
	response: Response,
	membership: Membership = Depends(require_core),
	side: str = Query(default="All"),
	tier: str = Query(default="All"),
	sportsbook: str = Query(default="All"),
	sport: str = Query(default="All"),
	category: str = Query(default="All"),
	search: str = Query(default=""),
	minConfidence: int = Query(default=0),
	sortBy: str = Query(default="time"),
	verdict: str = Query(default="All"),
	includePastDates: bool = Query(default=False),
	includeStarted: bool = Query(default=False),
	includeStale: bool = Query(default=False),
	onlyMoved: bool = Query(default=False),
	includeReliability: bool = Query(default=True),
	limit: int = Query(default=75, ge=1, le=500),
	offset: int = Query(default=0, ge=0),
	if_none_match: str | None = Header(default=None, alias="If-None-Match"),
) -> dict[str, object]:
	started_at = time.perf_counter()
	try:
		is_pro = membership.has_pro_access
		subscription_tier = str(membership.subscription_tier or "").strip().lower()
		has_strikeout_suggestive_pick = (
			subscription_tier in {"edge", "gold", "pro_gold", "pro-gold"}
			or membership.level >= AccessLevel.ADMIN
		)
		prop_list = _cached_prop_catalog()
		side_filter = side.strip().lower() if is_pro else "all"
		tier_filter = tier.strip().lower() if is_pro else "all"
		def _normalize_sportsbook_filter_key(value: str) -> str:
			normalized = str(value or "").strip().lower()
			normalized = normalized.replace(" ", "").replace("_", "").replace("-", "")
			if normalized == "all":
				return "all"
			if "betr" in normalized:
				return "betr"
			# DraftKings Pick6 arrives under several spellings. The sportsbook
			# DraftKings is a different book and must not collapse into it.
			if "pick6" in normalized or "pick06" in normalized:
				return "pick6"
			return normalized

		sportsbook_filter = _normalize_sportsbook_filter_key(sportsbook)
		sport_filter = sport.strip().lower().replace(" ", "")
		category_filter = category.strip().lower()
		search_filter = search.strip().lower()
		min_confidence = max(0, int(minConfidence)) if is_pro else 0
		sort_by = sortBy.strip().lower() if is_pro else "time"
		verdict_filter = verdict.strip().upper() if is_pro else "ALL"
		today_local = datetime.now(_scoreboard_timezone()).date()
		now_utc = datetime.now(timezone.utc)
		stale_after_minutes = max(
			5,
			int(os.getenv("PROP_FEED_STALE_MINUTES", "180")),
		)
		stale_fallback_minutes = max(
			stale_after_minutes + 30,
			int(os.getenv("PROP_FEED_STALE_FALLBACK_MINUTES", "360")),
		)
		catalog_has_fresh_row = any(
			not bool(getattr(prop, "dataStale", False))
			and not _is_stale_timestamp(
				str(getattr(prop, "lastUpdatedUtc", "") or ""),
				now_utc,
				stale_after_minutes,
			)
			for prop in prop_list
		)
		catalog_has_grace_row = False
		recovery_active = False
		if not includeStale and not catalog_has_fresh_row:
			catalog_has_grace_row = any(
				not bool(getattr(prop, "dataStale", False))
				and not _is_stale_timestamp(
					str(getattr(prop, "lastUpdatedUtc", "") or ""),
					now_utc,
					stale_fallback_minutes,
				)
				for prop in prop_list
			)
			# A recovery can legitimately take longer than the ordinary stale
			# grace window. Do not turn a non-empty last-known-good catalog into
			# an empty board while the worker is actively replacing it. The
			# replacement is published atomically, and every fallback row is
			# explicitly marked stale below so the UI cannot mistake it for a
			# freshly verified line.
			sync_state = _sync_state_snapshot()
			recovery_active = str(sync_state.get("status") or "").lower() in {
				"queued", "running"
			}
		serve_stale_fallback = (
			not includeStale
			and not catalog_has_fresh_row
			and bool(prop_list)
			and recovery_active
		)
		catalog_updated_at = max(
			(prop.lastUpdatedUtc for prop in prop_list),
			default="",
		)
		with _prop_catalog_lock:
			catalog_version = str(_prop_catalog.get("version") or "")
		cache_signature = json.dumps(
			[
				APP_VERSION,
				len(prop_list),
				catalog_updated_at,
				catalog_version,
				membership.user_id,
				int(membership.level),
				subscription_tier,
				side_filter,
				tier_filter,
				sportsbook_filter,
				sport_filter,
				category_filter,
				search_filter,
				min_confidence,
				sort_by,
				verdict_filter,
				includePastDates,
				includeStarted,
				includeStale,
				serve_stale_fallback,
				onlyMoved,
				includeReliability,
				limit,
				offset,
			],
			separators=(",", ":"),
		)
		cache_key = hashlib.sha256(cache_signature.encode()).hexdigest()
		etag = f'"{cache_key[:24]}"'
		cached_response = _cached_prop_response(cache_key)
		if cached_response is not None:
			cached_etag, cached_payload = cached_response
			response.headers["ETag"] = cached_etag
			response.headers["Cache-Control"] = "private, no-store, max-age=0"
			response.headers["Vary"] = "Authorization"
			response.headers["X-App-Version"] = APP_VERSION
			payload = cached_payload
			if if_none_match == cached_etag:
				response.status_code = 304
				payload = {}
			duration_ms = int((time.perf_counter() - started_at) * 1000)
			with _prop_metrics_lock:
				_prop_metrics.update(
					requests=int(_prop_metrics["requests"]) + 1,
					cacheHits=int(_prop_metrics.get("cacheHits") or 0) + 1,
					lastDurationMs=duration_ms,
					lastPayloadBytes=len(str(payload).encode("utf-8")),
					lastServedAt=datetime.now(timezone.utc).isoformat(),
					lastTotalCount=len(prop_list),
					lastDataUpdatedAt=catalog_updated_at or None,
					lastRequestSucceeded=True,
				)
			return payload

		def _is_mlb_strikeout_prop(prop: PropResponse) -> bool:
			sport_text = str(getattr(prop, "sport", "") or "").strip().upper()
			market_text = " ".join((
				str(getattr(prop, "market", "") or ""),
				str(getattr(prop, "marketKey", "") or ""),
				str(getattr(prop, "category", "") or ""),
			)).lower()
			return sport_text == "MLB" and "strikeout" in market_text

		def _recommendation_visible(prop: PropResponse) -> bool:
			if not bool(getattr(prop, "recommendationAvailable", False)):
				return False
			if _is_mlb_strikeout_prop(prop) and not has_strikeout_suggestive_pick:
				return False
			return True

		def _visible_recommendation_side(prop: PropResponse) -> str:
			if not _recommendation_visible(prop):
				return ""
			return str(prop.recommendedSide or "").strip().lower()

		def _visible_recommendation_tier(prop: PropResponse) -> str:
			if not _recommendation_visible(prop):
				return ""
			return str(prop.tier or "").strip().lower()

		def _pro_payload(prop: PropResponse) -> dict[str, object]:
			payload = prop.model_dump()
			if _is_mlb_strikeout_prop(prop) and not has_strikeout_suggestive_pick:
				payload.update({
					"recommendedSide": "N/A",
					"pick": "N/A",
					"pickText": "No Pick",
					"tier": "No Pick",
					"recommendationAvailable": False,
					"recommendationUnavailableReason": "pro_gold_required_for_strikeout_pick",
					"recommendationExplanation": "Suggestive strikeout picks require Pro Gold.",
				})
			return payload

		def _prop_payload(prop: PropResponse) -> dict[str, object]:
			payload = _pro_payload(prop) if is_pro else core_prop_payload(prop)
			if serve_stale_fallback and _is_stale_timestamp(
				str(getattr(prop, "lastUpdatedUtc", "") or ""),
				now_utc,
				stale_after_minutes,
			):
				payload["dataStale"] = True
			if not str(payload.get("imagePath") or "").strip():
				payload["imagePath"] = resolve_player_image(prop.player, prop.sport)
			return payload

		def _matches_filters(
			prop: PropResponse,
			*,
			apply_category: bool,
			apply_sportsbook: bool = True,
			apply_verdict: bool = True,
		) -> bool:
			# This predicate runs across the complete live catalog, often more
			# than 8,000 rows. Reading model attributes directly avoids creating
			# two full temporary dictionaries per prop on every request.
			start_time = _parse_start_time(prop.startTimeUtc)
			if not includePastDates:
				if start_time is None:
					return False
				event_date = start_time.astimezone(
					_scoreboard_timezone()
				).date()
				if event_date < today_local:
					return False
			if not includeStarted and start_time is not None and start_time <= now_utc:
				return False
			if not includeStale:
				if (
					bool(getattr(prop, "dataStale", False))
					and not serve_stale_fallback
				):
					return False
				if not serve_stale_fallback and _is_stale_timestamp(
					str(getattr(prop, "lastUpdatedUtc", "") or ""),
					now_utc,
					stale_after_minutes,
				):
					return False
			if onlyMoved:
				opening = float(getattr(prop, "openingLine", 0) or 0)
				current = float(getattr(prop, "currentLine", 0) or 0)
				if opening == 0 or current == 0 or abs(current - opening) < 0.01:
					return False
			recommended_side = _visible_recommendation_side(prop)
			recommended_tier = _visible_recommendation_tier(prop)
			confidence = int(prop.confidence or 0)
			prop_sportsbook = _normalize_sportsbook_filter_key(prop.sportsbook)
			prop_sport = str(prop.sport or "").strip().lower().replace(" ", "")
			prop_category = str(prop.category or "").strip().lower()
			searchable = " ".join((
				str(prop.player or ""),
				str(prop.matchup or ""),
				str(prop.market or ""),
				str(prop.category or ""),
			)).lower()

			if side_filter != "all" and recommended_side != side_filter:
				return False
			if tier_filter != "all" and recommended_tier != tier_filter:
				return False
			if (
				apply_sportsbook
				and sportsbook_filter != "all"
				and prop_sportsbook != sportsbook_filter
			):
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
			if apply_verdict and verdict_filter != "ALL":
				prop_verdict = (
					prop.verdict if isinstance(prop.verdict, dict) else {}
				)
				decision = str(prop_verdict.get("decision") or "").upper()
				actionable = bool(prop_verdict.get("actionable"))
				if verdict_filter == "ACTIONABLE":
					if not actionable:
						return False
				elif decision != verdict_filter:
					return False
			return True

		coverage_base_props = [
			prop for prop in prop_list
			if _matches_filters(
				prop, apply_category=False, apply_sportsbook=False
			)
		]
		# Category rails must distinguish inventory from props the model is
		# prepared to recommend. These counts deliberately ignore the selected
		# verdict tab while honoring every other active board filter.
		total_facet_props = [
			prop for prop in prop_list
			if _matches_filters(
				prop, apply_category=False, apply_verdict=False
			)
		]
		playable_facet_props = [
			prop for prop in total_facet_props
			if bool((getattr(prop, "verdict", None) or {}).get("actionable"))
		]
		facet_props = [
			prop for prop in prop_list
			if _matches_filters(prop, apply_category=False)
		]
		total_category_counts = Counter(
			str(prop.category or "other").strip().upper()
			for prop in total_facet_props
		)
		playable_category_counts = Counter(
			str(prop.category or "other").strip().upper()
			for prop in playable_facet_props
		)
		category_counts = Counter(
			str(prop.category or "other").strip().upper()
			for prop in facet_props
		)
		sport_counts = Counter(
			str(prop.sport or "other").strip().upper()
			for prop in facet_props
		)
		# Counted before the sportsbook filter is applied, so selecting one
		# book does not report every other book as empty.
		sportsbook_counts = Counter(
			_normalize_sportsbook_filter_key(
				str(prop.sportsbook or "other")
			)
			for prop in coverage_base_props
		)
		provider_coverage = (
			_provider_category_coverage(
				coverage_base_props,
				selected_site=sportsbook_filter,
			)
			if includeReliability
			else {}
		)
		provider_reliability = (
			build_provider_reliability(
				prop_list,
				expected_sites=PREFERRED_BOOKMAKERS,
				horizon_days=4,
				stale_after_minutes=stale_after_minutes,
				day_timezone=_scoreboard_timezone(),
			)
			if includeReliability
			else {}
		)
		recovery_reason = (
			"partial_provider_coverage"
			if includeReliability and provider_coverage.get("limited") is True
			else "stale_three_day_catalog"
			if includeReliability and provider_reliability.get("recoveryRecommended") is True
			else ""
		)
		if recovery_reason:
			queued_recovery = _enqueue_prop_refresh()
			recovery = {
				"requested": True,
				"queued": queued_recovery is not None,
				"reason": recovery_reason,
				"jobId": (
					str(queued_recovery.get("id") or "")
					if isinstance(queued_recovery, dict)
					else ""
				),
			}
		else:
			recovery = {
				"requested": False,
				"queued": False,
				"reason": "",
				"jobId": "",
			}
		if includeReliability:
			provider_reliability["recovery"] = recovery
			provider_coverage["recovery"] = recovery
		sport_category_counts: dict[str, Counter[str]] = {}
		for prop in facet_props:
			sport_key = str(prop.sport or "other").strip().upper()
			category_key = str(prop.category or "other").strip().upper()
			sport_category_counts.setdefault(sport_key, Counter())[category_key] += 1
		total_sport_category_counts: dict[str, Counter[str]] = {}
		for prop in total_facet_props:
			sport_key = str(prop.sport or "other").strip().upper()
			category_key = str(prop.category or "other").strip().upper()
			total_sport_category_counts.setdefault(sport_key, Counter())[category_key] += 1
		playable_sport_category_counts: dict[str, Counter[str]] = {}
		for prop in playable_facet_props:
			sport_key = str(prop.sport or "other").strip().upper()
			category_key = str(prop.category or "other").strip().upper()
			playable_sport_category_counts.setdefault(
				sport_key, Counter()
			)[category_key] += 1
		filtered_props = [
			prop for prop in facet_props
			if _matches_filters(prop, apply_category=True)
		]
		verdict_base_props = [
			prop for prop in prop_list
			if _matches_filters(
				prop,
				apply_category=True,
				apply_verdict=False,
			)
		]
		verdict_counts = Counter(
			str(
				(getattr(prop, "verdict", None) or {}).get("decision")
				or "UNJUDGED"
			).upper()
			for prop in verdict_base_props
		)
		verdict_counts["ALL"] = len(verdict_base_props)
		verdict_counts["ACTIONABLE"] = sum(
			1
			for prop in verdict_base_props
			if bool((getattr(prop, "verdict", None) or {}).get("actionable"))
		)

		tier_rank = {
			"premium": 3,
			"strong": 2,
			"lean": 1,
			"pass": 0,
			"no pick": 0,
		}

		def _all_sports_priority(row: PropResponse) -> int:
			if sport_filter != "all":
				return 0
			sport_label = str(row.sport or "").strip().upper()
			return 1 if sport_label == "SOCCER" or sport_label.startswith("SOCCER_") else 0

		def _start_time(row: PropResponse) -> datetime:
			return _parse_start_time(row.startTimeUtc) or datetime.max.replace(
				tzinfo=timezone.utc
			)

		def _stable_identity(row: PropResponse) -> tuple[str, str, str]:
			return (
				str(row.player or "").casefold(),
				str(row.market or "").casefold(),
				str(row.id or ""),
			)

		if sort_by == "edge":
			# Rank on probability, not stat units. A 3.0 edge on passing yards
			# and a 0.8 edge on strikeouts are not comparable quantities, and
			# neither accounts for the price being offered: the ordering was
			# dominated by whichever markets happened to have the widest
			# distributions. Probability edge is model minus de-vigged market,
			# so it is denominated the same way for every market and already
			# net of the book's margin. Expected value breaks ties, and the
			# stat-unit edge only orders props with no priced market at all.
			filtered_props.sort(
				key=lambda row: (
					_start_time(row),
					_all_sports_priority(row),
					-float(
						row.probabilityEdge
						if row.probabilityEdge is not None
						else -1
					),
					-float(row.evPercentage or 0),
					-float(row.edge or 0),
					*_stable_identity(row),
				),
			)
		elif sort_by == "trust":
			filtered_props.sort(
				key=lambda row: (
					_start_time(row),
					_all_sports_priority(row),
					-int(row.piTrustScore or 0),
					*_stable_identity(row),
				),
			)
		elif sort_by == "premium":
			filtered_props.sort(
				key=lambda row: (
					_start_time(row),
					_all_sports_priority(row),
					-tier_rank.get(
						_visible_recommendation_tier(row) or "no pick",
						0,
					),
					-int(row.confidence or 0),
					*_stable_identity(row),
				),
			)
		elif sort_by == "time":
			filtered_props.sort(
				key=lambda row: (
					_start_time(row),
					_all_sports_priority(row),
					*_stable_identity(row),
				),
			)
		else:
			filtered_props.sort(
				key=lambda row: (
					_start_time(row),
					_all_sports_priority(row),
					-int(row.confidence or 0),
					*_stable_identity(row),
				),
			)
			sort_by = "confidence"

		total_count = len(filtered_props)
		page = filtered_props[offset:offset + limit]
		model_pick_count = sum(
			1
			for prop in filtered_props
			if _recommendation_visible(prop)
			and str(getattr(prop, "recommendedSide", "") or "").strip().upper()
			in {"OVER", "UNDER"}
		)
		baseline_pick_count = sum(
			1
			for prop in filtered_props
			if _recommendation_visible(prop)
			and str(getattr(prop, "projectionModelVersion", "") or "")
			== BASELINE_MODEL_VERSION
		)
		baseline_projection_count = sum(
			1
			for prop in filtered_props
			if str(getattr(prop, "projectionModelVersion", "") or "")
			== BASELINE_MODEL_VERSION
		)
		provider_pick_count = max(0, model_pick_count - baseline_pick_count)

		def _has_market_direction(prop: PropResponse) -> bool:
			over = getattr(prop, "noVigOverProbability", None)
			under = getattr(prop, "noVigUnderProbability", None)
			return (
				over is not None
				and under is not None
				and abs(float(over) - float(under)) >= 0.005
			)

		market_pick_count = sum(
			1
			for prop in filtered_props
			if not _recommendation_visible(prop)
			and _has_market_direction(prop)
		)
		system_pick_count = model_pick_count + market_pick_count
		payload = {
			"count": total_count,
			"facetCount": len(facet_props),
			"categoryCounts": dict(sorted(category_counts.items())),
			"totalCategoryCounts": dict(sorted(total_category_counts.items())),
			"playableCategoryCounts": dict(
				sorted(playable_category_counts.items())
			),
			"sportCounts": dict(sorted(sport_counts.items())),
			# Lets the board hide a prop site that currently has nothing,
			# rather than offering a filter that returns an empty screen.
			"sportsbookCounts": dict(sorted(sportsbook_counts.items())),
			"providerCoverage": provider_coverage,
			"providerReliability": provider_reliability,
			"verdictCounts": dict(sorted(verdict_counts.items())),
			"sportCategoryCounts": {
				sport_key: dict(sorted(counts.items()))
				for sport_key, counts in sorted(sport_category_counts.items())
			},
			"totalSportCategoryCounts": {
				sport_key: dict(sorted(counts.items()))
				for sport_key, counts in sorted(total_sport_category_counts.items())
			},
			"playableSportCategoryCounts": {
				sport_key: dict(sorted(counts.items()))
				for sport_key, counts in sorted(playable_sport_category_counts.items())
			},
			"returned": len(page),
			"offset": offset,
			"limit": limit,
			"hasMore": offset + len(page) < total_count,
			"staleFallback": {
				"active": serve_stale_fallback,
				"reason": "recovery_running" if serve_stale_fallback else None,
				"normalFreshnessMinutes": stale_after_minutes,
				"maximumAgeMinutes": stale_fallback_minutes,
				"ageLimitBypassedDuringRecovery": (
					serve_stale_fallback and not catalog_has_grace_row
				),
			},
			"recommendationCoverage": {
				"modelPicks": model_pick_count,
				"baselinePicks": baseline_pick_count,
				"baselineProjections": baseline_projection_count,
				"suppressedWeakBaselineSignals": max(
					0,
					baseline_projection_count - baseline_pick_count,
				),
				"providerPicks": provider_pick_count,
				"marketPicks": market_pick_count,
				"systemPicks": system_pick_count,
				"pending": max(0, total_count - system_pick_count),
				"total": total_count,
			} if is_pro else {"total": total_count},
			"props": [_prop_payload(prop) for prop in page],
			"filters": {
				"side": side,
				"tier": tier,
				"sportsbook": sportsbook,
				"sport": sport,
				"category": category,
				"search": search,
				"minConfidence": min_confidence,
				"sortBy": sort_by,
				"verdict": verdict_filter,
				"includePastDates": includePastDates,
				"includeStarted": includeStarted,
				"onlyMoved": onlyMoved,
				"includeReliability": includeReliability,
			},
			"version": APP_VERSION,
			"feed": _catalog_feed_state(),
		}
		_remember_prop_response(
			cache_key,
			etag=etag,
			payload=payload,
		)
		response.headers["ETag"] = etag
		response.headers["Cache-Control"] = "private, no-store, max-age=0"
		response.headers["Vary"] = "Authorization"
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
				lastTotalCount=len(prop_list),
				lastDataUpdatedAt=catalog_updated_at or None,
				lastRequestSucceeded=True,
			)
		return payload
	except Exception as exc:
		with _prop_metrics_lock:
			_prop_metrics["requests"] = int(_prop_metrics["requests"]) + 1
			_prop_metrics["errors"] = int(_prop_metrics["errors"]) + 1
			_prop_metrics["lastRequestSucceeded"] = False
		raise HTTPException(
			status_code=500,
			detail=f"Unable to load props: {exc}",
		) from exc


@app.get("/api/props/ev")
def positive_ev_props(
	response: Response,
	min_ev: float = Query(default=0.0),
	sport: str = Query(default="All"),
	_membership: Membership = Depends(require_pro),
) -> dict[str, object]:
	"""Return only props backed by a genuine positive-EV calculation."""
	response.headers["Cache-Control"] = "private, no-store, max-age=0"
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


@app.get("/api/props/calibration")
def prop_calibration(
	minimum_sample: int = Query(default=20, ge=5, le=1000),
	_membership: Membership = Depends(require_pro),
) -> dict[str, object]:
	return prediction_calibration_report(minimum_sample)


@app.get("/api/props-test")
def props_test(
	_membership: Membership = Depends(require_pro),
) -> dict[str, object]:
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
			"book": "DraftKings Pick6",
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
def sync_props() -> dict[str, object]:
	if _sync_is_fresh():
		return {**_sync_state_snapshot(), "reusedFreshData": True,
			"message": "Current odds are still inside the server freshness window."}
	queued = _enqueue_requested_prop_sync()
	if queued is None:
		raise HTTPException(
			status_code=503,
			detail=(
				"The dedicated sync worker is unavailable. The saved catalog "
				"remains online and no provider work was started in the API."
			),
		)
	return {
		**_sync_state_snapshot(),
		"status": "queued",
		"job": queued,
		"message": "Global sports sync queued on the dedicated worker.",
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
def get_identity_map(_owner: str = Depends(require_owner)) -> dict[str, object]:
	return load_identity_map()


@app.post("/api/identity/bootstrap")
def bootstrap_identity_map(
	sourceProvider: str = Query(default="odds-api"),
	_owner: str = Depends(require_owner),
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
	_owner: str = Depends(require_owner),
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
	_owner: str = Depends(require_owner),
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
	_owner: str = Depends(require_owner),
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
	_owner: str = Depends(require_owner),
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
def get_player_availability_map(
	_owner: str = Depends(require_owner),
) -> dict[str, object]:
	return load_status_map()


@app.post("/api/player-availability/bulk")
def bulk_player_availability_update(
	body: dict[str, object] = Body(default={}),
	mode: str = Query(default="merge"),
	_owner: str = Depends(require_owner),
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
	_owner: str = Depends(require_owner),
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
	user_id: str = Depends(require_user_id),
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
				),
				user_id=user_id,
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
	if refresh and not _sync_is_fresh():
		# A line check must never run provider ingestion in the web process.
		# Queue a refresh and evaluate the saved catalog immediately.
		_enqueue_prop_refresh()

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
	user_id: str = Depends(require_user_id),
) -> list[PropBuilderHistory]:
	return list_prop_builder_history(
		limit=limit,
		user_id=user_id,
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
	player: str | None = None,
	user_id: str = Depends(require_user_id),
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
		player=player,
		user_id=user_id,
	)


@app.post(
	"/api/prop-builder/history/grade",
)
def grade_builder_history(
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	try:
		result = grade_prop_builder_history(user_id=user_id)
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
	user_id: str = Depends(require_user_id),
) -> PropBuilderHistory:
	build = get_prop_builder_history(
		history_id,
		user_id=user_id,
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
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	deleted = delete_prop_builder_history(
		history_id,
		user_id=user_id,
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
def remove_all_builder_history(
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	deleted_count = clear_prop_builder_history(user_id=user_id)
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


@app.post("/api/support/ticket-sync-diagnostic")
def submit_ticket_sync_diagnostic(
	request: TicketSyncDiagnostic,
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	return record_ticket_sync_diagnostic(request, user_id=user_id)


@app.post("/api/slips")
def save_slip(request: SlipCreate, user_id: str = Depends(require_user_id)) -> dict[str, object]:
	try:
		# Reconcile the client snapshot with the current authoritative feed before
		# enforcing the server-side start-time lock.
		requested_prop_ids = {leg.prop_id for leg in request.legs}
		current_props = {
			prop.id: prop
			for prop in _cached_prop_catalog()
			if prop.id in requested_prop_ids
		}
		for leg in request.legs:
			current = current_props.get(leg.prop_id)
			if current is None:
				continue
			status = str(current.gameStatus or "").strip().lower()
			if status in {"live", "in progress", "final", "finished", "completed"}:
				raise ValueError(
					f"Selection closed for {leg.player}: the game is already underway."
				)
			start = str(current.startTimeUtc or current.gameStartTime or "").strip()
			if start:
				leg.game_start_time = start
		slip = create_slip(request, user_id=user_id)
	except ValueError as exc:
		raise HTTPException(status_code=409, detail=str(exc)) from exc
	except Exception as exc:
		logging.exception("Ticket lock failed")
		raise HTTPException(
			status_code=503,
			detail="Ticket storage is temporarily unavailable. Please retry.",
		) from exc
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


@app.get("/api/slips/live-stats")
def get_live_slip_stats(
	season: str = Query(default=str(datetime.now().year)),
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	return _live_slip_stats_payload(season=season, user_id=user_id)


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


@app.delete("/api/slips/{slip_id}")
def unlock_slip(
	slip_id: str,
	user_id: str = Depends(require_user_id),
) -> dict[str, object]:
	deleted = delete_slip(slip_id, user_id=user_id)
	if not deleted:
		raise HTTPException(
			status_code=404,
			detail="Slip not found.",
		)

	realtime_hub.broadcast_user_from_thread(
		{"type": "ticket.deleted", "version": 1, "eventId": f"ticket-{slip_id}-deleted",
		 "occurredAt": datetime.now(timezone.utc).isoformat(),
		 "data": {"id": slip_id}}, "tickets", user_id,
	)

	return {"status": "deleted", "slip_id": slip_id}


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


@app.post("/api/slips/grade")
def grade_slips(user_id: str = Depends(require_user_id)) -> dict[str, object]:
	try:
		return grade_active_slips(user_id=user_id)
	except Exception as exc:
		logging.exception("Multi-sport slip grading failed")
		raise HTTPException(
			status_code=502,
			detail=f"Slip grading failed: {exc}",
		) from exc


@app.post("/api/slips/reconcile")
def reconcile_slips(user_id: str = Depends(require_user_id)) -> dict[str, object]:
	try:
		return reconcile_user_slips(user_id=user_id)
	except Exception as exc:
		logging.exception("Authoritative slip reconciliation failed")
		raise HTTPException(
			status_code=502,
			detail=f"Slip reconciliation failed: {exc}",
		) from exc


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
	cache_key = f"scoreboard:v3:{target_date.isoformat()}"
	cached_scoreboard = get_distributed_json(cache_key)
	if isinstance(cached_scoreboard, dict):
		cached_games = cached_scoreboard.get("games")
		if isinstance(cached_games, list):
			return cached_scoreboard

	# Scoreboard providers already return authoritative event timestamps.
	# Avoid rebuilding the complete prop catalog on a cold scoreboard request.
	shared_time_map: dict[str, dict[str, str]] = {}
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
		key = _scoreboard_dedupe_key(game)
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

	payload = {
		"date": target_date.isoformat(),
		"updated_at": now.isoformat(),
		"games": games,
	}
	today = now.astimezone(_scoreboard_timezone()).date()
	set_distributed_json(
		cache_key,
		payload,
		ttl_seconds=20 if target_date == today else 300,
	)
	return payload


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
	_owner: str = Depends(require_owner),
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


class _BackgroundJob:
	"""Runs a slow admin refresh outside the request/response cycle.

	Roster syncs that fetch dozens of team rosters sequentially (Sportmonks:
	6 leagues x ~20 teams each) can comfortably exceed Render's proxy
	timeout if run inline, which surfaces as a 502 even though the work
	would have finished fine given more time. Mirrors the existing
	/api/sync + /api/sync/status pattern: start the work via
	BackgroundTasks and return immediately, caller polls status.
	"""

	def __init__(self) -> None:
		self._run_lock = Lock()
		self._state_lock = Lock()
		self._state: dict[str, object] = {
			"status": "idle",
			"startedAt": None,
			"finishedAt": None,
			"result": None,
			"error": None,
		}

	def snapshot(self) -> dict[str, object]:
		with self._state_lock:
			return dict(self._state)

	def start(
		self,
		background_tasks: BackgroundTasks,
		work: Callable[[], object],
	) -> dict[str, object]:
		if not self._run_lock.acquire(blocking=False):
			return {**self.snapshot(), "alreadyRunning": True}

		with self._state_lock:
			self._state.update(
				status="running",
				startedAt=datetime.now(timezone.utc).isoformat(),
				finishedAt=None,
				result=None,
				error=None,
			)

		def _run() -> None:
			try:
				result = work()
				with self._state_lock:
					self._state.update(
						status="complete",
						finishedAt=datetime.now(timezone.utc).isoformat(),
						result=result,
						error=None,
					)
			except Exception as exc:
				logging.exception("Background admin refresh job failed")
				with self._state_lock:
					self._state.update(
						status="failed",
						finishedAt=datetime.now(timezone.utc).isoformat(),
						error=str(exc),
					)
			finally:
				self._run_lock.release()

		background_tasks.add_task(_run)
		return {**self.snapshot(), "message": "Refresh started in the background."}


_gridiron_ice_history_job = _BackgroundJob()
_golf_roster_job = _BackgroundJob()


@app.post("/api/admin/refresh-mlb-headshots")
def refresh_mlb_headshots(
	_owner: str = Depends(require_owner),
) -> dict[str, object]:
	bucket = int(time.time() // 300)
	queued = enqueue_background_job(
		"jobs.refresh_mlb_headshots",
		job_id=f"headshots:mlb:{bucket}",
	)
	if queued is None:
		raise HTTPException(
			status_code=503,
			detail="Background worker unavailable; MLB refresh was not started",
		)
	return {**queued, "message": "MLB headshot refresh queued on the worker."}


@app.get("/api/admin/refresh-mlb-headshots/status")
def refresh_mlb_headshots_status(_owner: str = Depends(require_owner)) -> dict[str, object]:
	return {
		"status": "worker-owned",
		"queue": job_queue_health(),
	}


@app.post("/api/admin/refresh-espn-headshots")
def refresh_espn_headshots(
	_owner: str = Depends(require_owner),
) -> dict[str, object]:
	bucket = int(time.time() // 300)
	queued = enqueue_background_job(
		"jobs.refresh_espn_headshots",
		job_id=f"headshots:espn:{bucket}",
	)
	if queued is None:
		raise HTTPException(
			status_code=503,
			detail="Background worker unavailable; ESPN refresh was not started",
		)
	return {**queued, "message": "ESPN headshot refresh queued on the worker."}


@app.get("/api/admin/refresh-espn-headshots/status")
def refresh_espn_headshots_status(_owner: str = Depends(require_owner)) -> dict[str, object]:
	return {
		"status": "worker-owned",
		"queue": job_queue_health(),
		"cache": espn_headshot_cache_health(),
	}



@app.post("/api/admin/refresh-gridiron-ice-history")
def refresh_gridiron_ice_history(
	background_tasks: BackgroundTasks,
	days: int = 7,
	_owner: str = Depends(require_owner),
) -> dict[str, object]:
	"""Ingest recent NFL and NHL box scores into the player game logs."""
	window = max(1, min(60, int(days)))
	return _gridiron_ice_history_job.start(
		background_tasks,
		lambda: run_gridiron_ice_backfill(days=window),
	)


@app.get("/api/admin/refresh-gridiron-ice-history/status")
def refresh_gridiron_ice_history_status(
	_owner: str = Depends(require_owner),
) -> dict[str, object]:
	return _gridiron_ice_history_job.snapshot()



@app.post("/api/admin/refresh-golf-roster")
def refresh_golf_roster(
	background_tasks: BackgroundTasks,
	_owner: str = Depends(require_owner),
) -> dict[str, object]:
	return _golf_roster_job.start(background_tasks, refresh_golf_roster_map)


@app.get("/api/admin/refresh-golf-roster/status")
def refresh_golf_roster_status(_owner: str = Depends(require_owner)) -> dict[str, object]:
	return _golf_roster_job.snapshot()


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
	_owner: str = Depends(require_owner),
) -> dict[str, object]:
	try:
		report = diagnose_wnba_game(game_id)
		return report.model_dump()
	except Exception as exc:
		raise HTTPException(
			status_code=500,
			detail=f"WNBA diagnosis failed: {exc}",
		) from exc
