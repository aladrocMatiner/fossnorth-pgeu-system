#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="docker-compose/.env"
TEMPLATE="keycloak/realm-pgeu.tmpl.json"
OUTPUT="keycloak/realm-pgeu.json"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template not found: $TEMPLATE" >&2
  exit 1
fi

# Load SITE BASE from .env or fallback
SITEBASE=$(grep -E '^DJANGO_SITE_BASE=' "$ENV_FILE" 2>/dev/null | sed -E 's/^DJANGO_SITE_BASE=//') || true
SITEBASE=${SITEBASE:-http://localhost:8000/}
# Normalize: drop trailing slash
SITEBASE=${SITEBASE%/}

mkdir -p keycloak
sed -e "s#\${SITEBASE}#${SITEBASE}#g" "$TEMPLATE" > "$OUTPUT".tmp
mv "$OUTPUT".tmp "$OUTPUT"

echo "Generated $OUTPUT with SITEBASE=${SITEBASE}"

