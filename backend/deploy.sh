#!/usr/bin/env bash
# One-shot Fly deploy for MorningVault market proxy (run on Mac Mini after `fly auth login`).
set -euo pipefail
cd "$(dirname "$0")"
export PATH="${HOME}/.fly/bin:${PATH}"

APP="morningvault"
REGION="iad"
VOLUME="market_cache"

if ! flyctl auth whoami &>/dev/null; then
  echo "Not logged in. Run: flyctl auth login"
  exit 1
fi

if ! flyctl apps list 2>/dev/null | grep -q "^${APP}[[:space:]]"; then
  echo "Creating app ${APP}..."
  flyctl apps create "${APP}" --org personal 2>/dev/null || flyctl apps create "${APP}"
fi

if ! flyctl volumes list -a "${APP}" 2>/dev/null | grep -q "${VOLUME}"; then
  echo "Creating volume ${VOLUME} in ${REGION}..."
  flyctl volumes create "${VOLUME}" --size 1 --region "${REGION}" -a "${APP}" --yes
fi

if [[ -z "${POLYGON_API_KEY:-}" ]]; then
  echo "Export POLYGON_API_KEY, then re-run this script."
  exit 1
fi

flyctl secrets set "POLYGON_API_KEY=${POLYGON_API_KEY}" -a "${APP}"
flyctl deploy -a "${APP}"

echo ""
echo "https://${APP}.fly.dev/health"
curl -fsS "https://${APP}.fly.dev/health" && echo ""
curl -fsS "https://${APP}.fly.dev/market/batch?symbols=SPY,BTC" | head -c 500 && echo ""