#!/usr/bin/env bash
# Generate monitoring configs from templates using env var substitution.
# Alertmanager and Prometheus don't support native env vars,
# so we render templates before deploying.
#
# Usage: ./scripts/generate-monitoring-configs.sh
#   Reads from .env in repo root, renders templates in monitoring/

set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Copy from envs/ first: cp envs/local.env .env"
  exit 1
fi

# shellcheck disable=SC1091
set -a && source .env && set +a

# Alertmanager — requires TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "WARN: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set — alertmanager alerts won't deliver"
fi
envsubst < monitoring/alertmanager/alertmanager.yml > monitoring/alertmanager/alertmanager.rendered.yml
echo "✅ monitoring/alertmanager/alertmanager.rendered.yml"

# Prometheus — uses template with node IP substitution
if [ -f monitoring/prometheus/prometheus.yml.template ]; then
  envsubst < monitoring/prometheus/prometheus.yml.template > monitoring/prometheus/prometheus.yml
  echo "✅ monitoring/prometheus/prometheus.yml"
fi

echo "Done. Mount rendered configs in compose (alertmanager.rendered.yml)."
