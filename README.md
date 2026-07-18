# PROP INTELLIGENCE

PROP INTELLIGENCE is a Flutter sports analytics application backed by a
FastAPI service and Supabase authentication/data storage.

## Production addresses

- Public website: `https://propsintell.com`
- Web application: `https://app.propsintell.com`
- Backend API: `https://api.propsintell.com`

## Local development

Install Flutter and Python dependencies, then run:

```powershell
flutter pub get
flutter run -d chrome `
  --dart-define=API_BASE_URL=http://127.0.0.1:8010 `
  --dart-define=SUPABASE_URL=https://doncoxjilytojmnpukxi.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY `
  --dart-define=AUTH_EMAIL_REDIRECT_URL=http://localhost:8080
```

The Python API can be started with:

```powershell
python -m uvicorn main:app --app-dir python_backend --reload --port 8010
```

## Production web build

Render executes `render_build_web.sh`. The build requires:

- `API_BASE_URL=https://api.propsintell.com`
- `SUPABASE_URL=https://doncoxjilytojmnpukxi.supabase.co`
- `SUPABASE_ANON_KEY=<Supabase publishable key>`
- `AUTH_EMAIL_REDIRECT_URL=https://app.propsintell.com`

The Supabase publishable/anon key is designed for browser use. Database
passwords, service-role keys, provider API keys, and other private credentials
must never be included in Flutter build arguments.

Public signup is disabled in the UI unless `ALLOW_PUBLIC_SIGNUP=true` is
explicitly supplied at build time. During private beta, signup must also remain
disabled in Supabase Authentication settings.

## Validation

```powershell
flutter analyze
flutter test
flutter build web --release
```

After applying the Supabase migrations and running historical ingestion, audit
production data coverage before advertising calibrated probabilities:

```powershell
.\.venv\Scripts\python.exe python_backend\scripts\validate_intelligence_readiness.py
```

Apply every repository migration in dependency order from a trusted deployment
terminal. The runner records checksums and will not silently reapply or mutate a
previously deployed migration:

```powershell
$env:DATABASE_URL='postgresql://...'
.\.venv\Scripts\python.exe python_backend\scripts\apply_supabase_migrations.py
.\.venv\Scripts\python.exe python_backend\scripts\sync_historical_daily.py
.\.venv\Scripts\python.exe python_backend\scripts\validate_intelligence_readiness.py
```

Do not place the database URL in source control. Configure it as a secret in
Render and use the Supabase direct database connection string for migrations.

The command exits successfully only when required tables exist, minimum data
coverage is present, and at least 100 prediction snapshots have been graded.

Saved tickets and closing-line snapshots use `SLIP_DATABASE_PATH`. The Render
blueprint mounts `/var/data` as persistent storage so deployments do not erase
ticket history. In production, verify `/health/storage` reports
`persistent-disk`. Disk-backed SQLite assumes one API instance; migrate ticket
storage to PostgreSQL before horizontally scaling the API.

Live odds default to `ODDS_REGIONS=us,us2` because provider quota cost scales
with both markets and regions. Configure `ODDS_REGIONS` and
`PREFERRED_BOOKMAKERS` explicitly if the product expands beyond the current
US/DFS audience. Sync cooldown automatically increases from 5 minutes to 30
minutes when quota is low and to 60 minutes when 10 or fewer credits remain.
Before each event-level odds request, the sync pipeline estimates its maximum
market-by-region cost and preserves `ODDS_API_QUOTA_RESERVE` credits (25 by
default). Events skipped by this guard are reported in sync status rather than
failing the entire board refresh.
Events are processed by nearest start time first, so a quota-limited refresh
completes the most actionable portion of the current slate before later games.
