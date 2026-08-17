#!/usr/bin/env bash
set -euo pipefail

FLUTTER_HOME="${HOME}/flutter"

if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
    echo "Installing Flutter..."
    git clone \
      --depth 1 \
      --branch stable \
      https://github.com/flutter/flutter.git \
      "${FLUTTER_HOME}"
  fi
  export PATH="${FLUTTER_HOME}/bin:${PATH}"
fi

# Ensure flutter is on PATH
export PATH="${FLUTTER_HOME}/bin:${PATH}"

echo "Flutter version:"
flutter --version

# Set defaults from vercel.json if not provided
: "${API_BASE_URL:=https://api.propsintell.com}"
: "${SUPABASE_URL:=https://doncoxjilytojmnpukxi.supabase.co}"
: "${AUTH_EMAIL_REDIRECT_URL:=https://app.propsintell.com}"
: "${ALLOW_PUBLIC_SIGNUP:=true}"
: "${TURNSTILE_SITE_KEY:=}"
: "${TURNSTILE_BASE_URL:=https://app.propsintell.com/}"

# Supabase rejects password authentication without a CAPTCHA token when its
# CAPTCHA protection is enabled. Never publish a production client that cannot
# create the token required by login, signup, and password recovery.
if [ "${VERCEL_ENV:-}" = "production" ] && [ -z "${TURNSTILE_SITE_KEY}" ]; then
  echo "TURNSTILE_SITE_KEY is required for production authentication." >&2
  exit 1
fi

if [ "${VERCEL_ENV:-}" = "production" ]; then
  TURNSTILE_REQUIRED="true"
else
  TURNSTILE_REQUIRED="false"
fi

# Accept the legacy lowercase Preview variable while keeping the canonical
# uppercase name used by production and the Flutter build.
if [ -z "${SUPABASE_ANON_KEY:-}" ] && [ -n "${supabase_anon_key:-}" ]; then
  SUPABASE_ANON_KEY="${supabase_anon_key}"
fi

# Preview deployments validate the production bundle but do not authenticate
# real users. Keep the production key mandatory while allowing PR previews to
# compile with an intentionally unusable public placeholder.
if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  if [ "${VERCEL_ENV:-}" = "preview" ]; then
    SUPABASE_ANON_KEY="preview-placeholder"
    ALLOW_PUBLIC_SIGNUP="false"
  else
    echo "SUPABASE_ANON_KEY is required for production builds." >&2
    exit 1
  fi
fi

if [ -z "${REVENUECAT_PUBLIC_API_KEY:-}" ]; then
  if [ "${VERCEL_ENV:-}" = "preview" ]; then
    REVENUECAT_PUBLIC_API_KEY="preview-placeholder"
  else
    echo "REVENUECAT_PUBLIC_API_KEY is required for production builds." >&2
    exit 1
  fi
fi

APP_VERSION="${VERCEL_GIT_COMMIT_SHA:-${APP_VERSION:-unknown}}"

flutter config --no-analytics
flutter clean
flutter pub get

echo "Building Flutter web..."
flutter build web --release \
  -O4 \
  --no-source-maps \
  --no-wasm-dry-run \
  --base-href="/" \
  --dart-define="API_BASE_URL=${API_BASE_URL}" \
  --dart-define="APP_VERSION=${APP_VERSION}" \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}" \
  --dart-define="AUTH_EMAIL_REDIRECT_URL=${AUTH_EMAIL_REDIRECT_URL}" \
  --dart-define="MOBILE_AUTH_REDIRECT_URL=com.propintelligence.app://login-callback/" \
  --dart-define="ALLOW_PUBLIC_SIGNUP=${ALLOW_PUBLIC_SIGNUP:-true}" \
  --dart-define="TURNSTILE_SITE_KEY=${TURNSTILE_SITE_KEY}" \
  --dart-define="TURNSTILE_REQUIRED=${TURNSTILE_REQUIRED}" \
  --dart-define="TURNSTILE_BASE_URL=${TURNSTILE_BASE_URL}" \
  --dart-define="REVENUECAT_PUBLIC_API_KEY=${REVENUECAT_PUBLIC_API_KEY}"

# Give every release a distinct app-shell cache and force stale clients to
# activate the current production bundle on their next visit.
sed -i "s/__PI_BUILD_VERSION__/${APP_VERSION}/g" build/web/OneSignalSDKWorker.js

echo "Build complete! Output in build/web"
