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
