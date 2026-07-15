import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
CONFIG_PACKAGE_DIR = BASE_DIR / "config"

# Keep backward compatibility with `from config import ...` while enabling
# `from config.<module> import ...` for files under python_backend/config/.
if CONFIG_PACKAGE_DIR.is_dir():
    __path__ = [str(CONFIG_PACKAGE_DIR)]

load_dotenv(BASE_DIR / ".env")

ODDS_API_KEY = os.getenv("ODDS_API_KEY", "").strip()
API_SPORTS_KEY = os.getenv("API_SPORTS_KEY", "").strip()
API_SPORTS_BASEBALL_KEY = os.getenv(
    "API_SPORTS_BASEBALL_KEY",
    API_SPORTS_KEY,
).strip()
WNBA_LEAGUE_ID = os.getenv("WNBA_LEAGUE_ID", "").strip()
DATABASE_URL = (os.getenv("DATABASE_URL") or "").strip()
DATABASE_SSLMODE = os.getenv("DATABASE_SSLMODE", "require").strip() or "require"
CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ALLOWED_ORIGINS",
        (
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
ODDS_REGIONS = "us,us2,eu,uk,au"
PREFERRED_BOOKMAKERS = [
    "prizepicks",
    "underdog",
    "draftkings",
    "sleeper",
    "fanduel",
    "betr",
]
PREFERRED_BOOKMAKERS_CSV = ",".join(PREFERRED_BOOKMAKERS)
DEFAULT_LOOKAHEAD_HOURS = 72
NEXT_AVAILABLE_MAX_DAYS = 7
HTTP_TIMEOUT_SECONDS = 12
DB_PATH = BASE_DIR / "prop_intelligence_cache.db"
