#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
FAILURES=0

info()  { printf '[-] %s\n' "$1"; }
pass()  { printf '[OK] %s\n' "$1"; }
fail()  { printf '[XX] %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

require_cmd() {
  local label="$1"
  local cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label (command '$cmd' not found)"
  fi
}

check_file_contains() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  if [[ ! -f "$file" ]]; then
    fail "$label (missing $file)"
    return
  fi
  if grep -qF "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label (pattern '$pattern' not found in $file)"
  fi
}

info "Checking required commands…"
require_cmd "Docker available" docker
require_cmd "docker compose plugin available" docker
if ! docker compose version >/dev/null 2>&1; then
  fail "docker compose version"
else
  pass "docker compose version"
fi

info "Checking repository structure…"
[[ -d "$ROOT_DIR/docker-compose" ]] && pass "Found docker-compose/" || fail "Missing docker-compose/"
[[ -f "$ROOT_DIR/docker-compose.yml" ]] && pass "Found docker-compose.yml" || fail "Missing docker-compose.yml"
[[ -d "$ROOT_DIR/pgeu-system" ]] && pass "Found pgeu-system/" || fail "Missing pgeu-system/"

ENV_FILE="docker-compose/.env"
if [[ -f "$ENV_FILE" ]]; then
  pass "Found docker-compose/.env"
  if grep -q '^DJANGO_DEBUG=true' "$ENV_FILE"; then
    fail "DJANGO_DEBUG must be false in docker-compose/.env"
  else
    pass "DJANGO_DEBUG is set to false"
  fi
else
  fail "Missing docker-compose/.env"
fi

REQ_FILE="pgeu-system/tools/devsetup/dev_requirements.txt"
info "Checking critical dependency pins…"
check_file_contains "pycryptodomex>=3.19.1" "$REQ_FILE" "pycryptodomex==3.19.1"
check_file_contains "qrcode==7.4.2" "$REQ_FILE" "qrcode==7.4.2"
check_file_contains "cairosvg==2.7.1" "$REQ_FILE" "cairosvg==2.7.1"
check_file_contains "PyMuPDF==1.24.9" "$REQ_FILE" "PyMuPDF==1.24.9"

# Optional OAuth checks
if grep -q '^DJANGO_ENABLE_OAUTH_AUTH=true' "$ENV_FILE"; then
  info "OAuth enabled; checking Keycloak env…"
  grep -q '^KEYCLOAK_BASE_URL=' "$ENV_FILE" && pass "KEYCLOAK_BASE_URL present" || fail "Missing KEYCLOAK_BASE_URL in docker-compose/.env"
  grep -q '^KEYCLOAK_CLIENT_ID=' "$ENV_FILE" && pass "KEYCLOAK_CLIENT_ID present" || fail "Missing KEYCLOAK_CLIENT_ID in docker-compose/.env"
  grep -q '^KEYCLOAK_CLIENT_SECRET=' "$ENV_FILE" && pass "KEYCLOAK_CLIENT_SECRET present" || fail "Missing KEYCLOAK_CLIENT_SECRET in docker-compose/.env"
fi

if [[ $FAILURES -eq 0 ]]; then
  echo "✅ Preflight completed successfully. Continue with 'docker compose build --no-cache && docker compose up -d'."
else
  echo "❌ Found $FAILURES issue(s). Fix the items above before continuing."
  exit 1
fi
