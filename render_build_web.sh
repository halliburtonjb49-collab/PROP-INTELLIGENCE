#!/usr/bin/env bash
set -euo pipefail

FLUTTER_HOME="${HOME}/flutter"

if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
    git clone \
      --depth 1 \
      --branch stable \
      https://github.com/flutter/flutter.git \
      "${FLUTTER_HOME}"
  fi
  export PATH="${FLUTTER_HOME}/bin:${PATH}"
fi

: "${API_BASE_URL:?API_BASE_URL is required}"
: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is required}"
: "${AUTH_EMAIL_REDIRECT_URL:?AUTH_EMAIL_REDIRECT_URL is required}"

flutter config --no-analytics
flutter pub get
flutter build web --release \
  --dart-define="API_BASE_URL=${API_BASE_URL}" \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}" \
  --dart-define="AUTH_EMAIL_REDIRECT_URL=${AUTH_EMAIL_REDIRECT_URL}" \
  --dart-define="ALLOW_PUBLIC_SIGNUP=${ALLOW_PUBLIC_SIGNUP:-true}" \
  --dart-define="REVENUECAT_PUBLIC_API_KEY=${REVENUECAT_PUBLIC_API_KEY:-}"
