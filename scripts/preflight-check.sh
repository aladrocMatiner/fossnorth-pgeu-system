#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

info()  { printf '[-] %s\n' "$1"; }
pass()  { printf '[OK] %s\n' "$1"; }
fail()  { printf '[!!] %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

require_cmd() {
  local label="$1"
  local cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label (no se encuentra '$cmd' en PATH)"
  fi
}

check_file_contains() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  if [[ ! -f "$file" ]]; then
    fail "$label (falta $file)"
    return
  fi
  if grep -qF "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label (no se encontró '$pattern' en $file)"
  fi
}

info "Verificando comandos básicos…"
require_cmd "Docker instalado" docker
require_cmd "Plugin docker compose disponible" "docker"
if ! docker compose version >/dev/null 2>&1; then
  fail "docker compose version"
else
  pass "docker compose version"
fi

info "Verificando estructura del repositorio…"
[[ -d "$ROOT_DIR/docker-compose" ]] && pass "Directorio docker-compose/" || fail "Directorio docker-compose/"
[[ -f "$ROOT_DIR/docker-compose.yml" ]] && pass "Fichero docker-compose.yml" || fail "Fichero docker-compose.yml"
[[ -d "$ROOT_DIR/pgeu-system" ]] && pass "Directorio pgeu-system/" || fail "Directorio pgeu-system/"

ENV_FILE="$ROOT_DIR/docker-compose/.env"
if [[ -f "$ENV_FILE" ]]; then
  pass "Fichero docker-compose/.env"
  if grep -q '^DJANGO_DEBUG=true' "$ENV_FILE"; then
    fail "DJANGO_DEBUG debe ser false en $ENV_FILE"
  else
    pass "DJANGO_DEBUG configurado a false"
  fi
else
  fail "Fichero docker-compose/.env"
fi

REQ_FILE="$ROOT_DIR/pgeu-system/tools/devsetup/dev_requirements.txt"
info "Verificando versiones de dependencias críticas…"
check_file_contains "pycryptodomex>=3.19.1" "$REQ_FILE" "pycryptodomex==3.19.1"
check_file_contains "qrcode==7.4.2" "$REQ_FILE" "qrcode==7.4.2"
check_file_contains "cairosvg==2.7.1" "$REQ_FILE" "cairosvg==2.7.1"
check_file_contains "PyMuPDF==1.24.9" "$REQ_FILE" "PyMuPDF==1.24.9"

if [[ $FAILURES -eq 0 ]]; then
  echo "✅ Preflight completado sin errores. Puedes continuar con 'docker compose build --no-cache && docker compose up -d'."
else
  echo "❌ Se detectaron $FAILURES problema(s). Corrige los puntos anteriores antes de continuar."
  exit 1
fi
