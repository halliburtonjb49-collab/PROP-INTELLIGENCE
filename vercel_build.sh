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

# Only SUPABASE_ANON_KEY is required from environment
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is required}"

APP_VERSION="${VERCEL_GIT_COMMIT_SHA:-${APP_VERSION:-unknown}}"

flutter config --no-analytics
flutter clean
flutter pub get

echo "Building Flutter web..."
flutter build web --release \
  --dart-define="API_BASE_URL=${API_BASE_URL}" \
  --dart-define="APP_VERSION=${APP_VERSION}" \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}" \
  --dart-define="AUTH_EMAIL_REDIRECT_URL=${AUTH_EMAIL_REDIRECT_URL}" \
  --dart-define="MOBILE_AUTH_REDIRECT_URL=com.propintelligence.app://login-callback/" \
  --dart-define="ALLOW_PUBLIC_SIGNUP=${ALLOW_PUBLIC_SIGNUP:-true}" \
  --dart-define="REVENUECAT_PUBLIC_API_KEY=${REVENUECAT_PUBLIC_API_KEY:-}"

echo "Build complete! Output in build/web"
