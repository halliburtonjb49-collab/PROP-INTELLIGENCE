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
SPORTSDATAIO_API_KEY = os.getenv("SPORTSDATAIO_API_KEY", "").strip()
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
ODDS_REGIONS = os.getenv("ODDS_REGIONS", "us,us2").strip() or "us,us2"
PREFERRED_BOOKMAKERS = [
    bookmaker.strip().lower()
    for bookmaker in os.getenv(
        "PREFERRED_BOOKMAKERS",
        "prizepicks,underdog,draftkings,sleeper,fanduel,betr",
    ).split(",")
    if bookmaker.strip()
]
PREFERRED_BOOKMAKERS_CSV = ",".join(PREFERRED_BOOKMAKERS)
DEFAULT_LOOKAHEAD_HOURS = 72
NEXT_AVAILABLE_MAX_DAYS = 7
HTTP_TIMEOUT_SECONDS = 12
LIVE_ODDS_SYNC_MIN_SECONDS = max(
    60, int(os.getenv("LIVE_ODDS_SYNC_MIN_SECONDS", "300"))
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
