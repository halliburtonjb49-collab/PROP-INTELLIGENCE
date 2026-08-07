import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
CONFIG_PACKAGE_DIR = BASE_DIR / "config"
PLAYER_IMAGE_DIR = BASE_DIR.parent / "assets" / "players"

# Keep backward compatibility with `from config import ...` while enabling
# `from config.<module> import ...` for files under python_backend/config/.
if CONFIG_PACKAGE_DIR.is_dir():
    __path__ = [str(CONFIG_PACKAGE_DIR)]

load_dotenv(BASE_DIR / ".env")

ODDS_API_KEY = os.getenv("ODDS_API_KEY", "").strip()
ODDS_API_KEY_SECONDARY = os.getenv("ODDS_API_KEY_SECONDARY", "").strip()
API_SPORTS_KEY = os.getenv("API_SPORTS_KEY", "").strip()
API_SPORTS_BASEBALL_KEY = os.getenv(
    "API_SPORTS_BASEBALL_KEY",
    API_SPORTS_KEY,
).strip()
WNBA_LEAGUE_ID = os.getenv("WNBA_LEAGUE_ID", "").strip()
SPORTMONKS_API_KEY = os.getenv("SPORTMONKS_API_KEY", "").strip()
SPORTMONKS_CRICKET_API_KEY = os.getenv("SPORTMONKS_CRICKET_API_KEY", "").strip()
SPORTSDATAIO_API_KEY = os.getenv("SPORTSDATAIO_API_KEY", "").strip()
CRICKETDATA_API_KEY = os.getenv("CRICKETDATA_API_KEY", "").strip()
BALLDONTLIE_API_KEY = os.getenv("BALLDONTLIE_API_KEY", "").strip()
SPORTRADAR_WNBA_API_KEY = os.getenv("SPORTRADAR_WNBA_API_KEY", "").strip()
SPORTRADAR_API_KEY = os.getenv(
    "SPORTRADAR_API_KEY", SPORTRADAR_WNBA_API_KEY,
).strip()
SPORTRADAR_ACCESS_LEVEL = os.getenv("SPORTRADAR_ACCESS_LEVEL", "trial").strip() or "trial"
SPORTSGAMEODDS_API_KEY = os.getenv("SPORTSGAMEODDS_API_KEY", "").strip()
DATABASE_URL = (os.getenv("DATABASE_URL") or "").strip()
DATABASE_SSLMODE = os.getenv("DATABASE_SSLMODE", "require").strip() or "require"
CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ALLOWED_ORIGINS",
        (
            "https://app.propsintell.com,"
            "https://www.propsintell.com,https://propsintell.com,"
            "http://localhost:3000,http://localhost:8080"
        ),
    ).split(",")
    if origin.strip()
]

if not ODDS_API_KEY:
    raise RuntimeError(
        "ODDS_API_KEY is missing from python_backend/.env"
    )
if not API_SPORTS_KEY:
    raise RuntimeError(
        "API_SPORTS_KEY is missing from python_backend/.env"
    )

BASE_URL = "https://api.the-odds-api.com/v4"
ODDS_REGIONS = (
    os.getenv("ODDS_REGIONS", "us,us2,us_dfs").strip()
    or "us,us2,us_dfs"
)
# How far ahead an event may start and still be worth spending credits on.
# The provider lists a sport's whole published schedule, so in August the NFL
# returns all 272 regular-season games -- the entire season -- and each one
# costs the same to price as tonight's. Those distant games carry almost no
# player markets yet, so the spend buys nothing and the sports later in the
# cycle are reached with the keys already exhausted. Zero disables the bound.
ODDS_EVENT_HORIZON_DAYS = max(
    0, int(os.getenv("ODDS_EVENT_HORIZON_DAYS", "7") or 7)
)

# The nearest events a sport keeps even when its whole schedule sits beyond
# the horizon. A date bound alone silently deletes any sport whose season
# starts later than the window: in early August every NFL game is a month
# out, so a seven-day bound took the sport from 445 props to none. This
# floor keeps the front of each schedule reachable while still refusing to
# price the season behind it.
ODDS_MINIMUM_EVENTS_PER_SPORT = max(
    0, int(os.getenv("ODDS_MINIMUM_EVENTS_PER_SPORT", "24") or 24)
)

_DEFAULT_BOOKMAKERS = "prizepicks,underdog,draftkings,pick6,fanduel,betr_us_dfs"

# Keys the odds provider does not have. Asking for one is silent -- the
# response simply omits it -- so a stale entry costs a book with no error
# to notice. `sleeper` was requested for months and could never return
# anything, because the provider has no such bookmaker.
_RETIRED_BOOKMAKERS = frozenset({"sleeper"})

# The provider's DFS catalogue. Deployment environments drift from the
# repository -- a value set in a dashboard outranks this file, and stays
# behind when the file moves on -- so these are restored if a configured
# list has fallen behind rather than silently losing coverage.
_REQUIRED_DFS_BOOKMAKERS = ("prizepicks", "underdog", "betr_us_dfs", "pick6")


def _resolve_bookmakers(raw: str) -> tuple[list[str], list[str], list[str]]:
    """Configured books, minus retired keys, plus any missing DFS site."""

    configured = [
        bookmaker.strip().lower()
        for bookmaker in raw.split(",")
        if bookmaker.strip()
    ]
    dropped = [key for key in configured if key in _RETIRED_BOOKMAKERS]
    resolved = [key for key in configured if key not in _RETIRED_BOOKMAKERS]
    added = [key for key in _REQUIRED_DFS_BOOKMAKERS if key not in resolved]
    resolved.extend(added)
    return resolved, dropped, added


(
    PREFERRED_BOOKMAKERS,
    RETIRED_BOOKMAKERS_DROPPED,
    MISSING_BOOKMAKERS_RESTORED,
) = _resolve_bookmakers(os.getenv("PREFERRED_BOOKMAKERS", _DEFAULT_BOOKMAKERS))
PREFERRED_BOOKMAKERS_CSV = ",".join(PREFERRED_BOOKMAKERS)
DEFAULT_LOOKAHEAD_HOURS = 72
NEXT_AVAILABLE_MAX_DAYS = 7
HTTP_TIMEOUT_SECONDS = 12
LIVE_ODDS_SYNC_MIN_SECONDS = min(
    120,
    max(60, int(os.getenv("LIVE_ODDS_SYNC_MIN_SECONDS", "120"))),
)
ODDS_API_LOW_QUOTA_THRESHOLD = max(
    0, int(os.getenv("ODDS_API_LOW_QUOTA_THRESHOLD", "100"))
)
ODDS_API_QUOTA_RESERVE = max(
    0, int(os.getenv("ODDS_API_QUOTA_RESERVE", "25"))
)
_render_cache_path = Path("/var/data/prop_intelligence_cache.db")
_default_cache_path = (
    _render_cache_path
    if os.getenv("RENDER", "").lower() == "true" and _render_cache_path.parent.is_dir()
    else BASE_DIR / "prop_intelligence_cache.db"
)
DB_PATH = Path(os.getenv("PROP_CACHE_DB_PATH", str(_default_cache_path))).expanduser()

_render_sportmonks_headshot_path = Path(
    "/var/data/sportmonks_headshot_map.json"
)
_default_sportmonks_headshot_path = (
    _render_sportmonks_headshot_path
    if os.getenv("RENDER", "").lower() == "true"
    and _render_sportmonks_headshot_path.parent.is_dir()
    else BASE_DIR / "data" / "sportmonks_headshot_map.json"
)
SPORTMONKS_HEADSHOT_MAP_PATH = Path(
    os.getenv(
        "SPORTMONKS_HEADSHOT_MAP_PATH",
        str(_default_sportmonks_headshot_path),
    )
).expanduser()

_render_espn_headshot_path = Path("/var/data/espn_headshot_map.json")
_default_espn_headshot_path = (
    _render_espn_headshot_path
    if os.getenv("RENDER", "").lower() == "true"
    and _render_espn_headshot_path.parent.is_dir()
    else BASE_DIR / "data" / "espn_headshot_map.json"
)
ESPN_HEADSHOT_MAP_PATH = Path(
    os.getenv(
        "ESPN_HEADSHOT_MAP_PATH",
        str(_default_espn_headshot_path),
    )
).expanduser()
