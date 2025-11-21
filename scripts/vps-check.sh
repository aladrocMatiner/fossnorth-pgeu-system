#!/usr/bin/env bash
set -euo pipefail

# End-to-end check via nginx for a given host.
# Defaults are derived from .env when present.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/docker-compose/.env"

default_host="new.foss-north.se"
default_scheme="https"
if [[ -f "$ENV_FILE" ]]; then
  host_line=$(grep -E '^DJANGO_SITE_BASE=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)
  if [[ -n "$host_line" ]]; then
    default_scheme="${host_line%%://*}"
    default_host="${host_line#*://}"
    default_host="${default_host%%/*}"
  fi
fi

HOSTNAME="${HOSTNAME_OVERRIDE:-$default_host}"
TARGET_IP="${TARGET_IP:-127.0.0.1}"
SCHEME="${SCHEME_OVERRIDE:-$default_scheme}"

kc_base_env=$(grep -E '^KEYCLOAK_BASE_URL=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)
KC_BASE="${KC_BASE_OVERRIDE:-${kc_base_env:-https://auth.foss-north.se/realms/pgeu}}"
KC_SCHEME="${KC_SCHEME_OVERRIDE:-${KC_BASE%%://*}}"
kc_host_path="${KC_BASE#*://}"
kc_host_path="${kc_host_path#/}"
kc_host="${KC_HOST_OVERRIDE:-${kc_host_path%%/*}}"
kc_path="/${kc_host_path#*/}"
[[ "$kc_path" == "/${kc_host_path}" ]] && kc_path=""
KC_PATH="${KC_PATH_OVERRIDE:-${kc_path%/}/.well-known/openid-configuration}"
KC_URL="${KC_URL_OVERRIDE:-${KC_SCHEME}://${kc_host}${KC_PATH}}"
KC_TARGET_IP="${KC_TARGET_IP:-$TARGET_IP}"

curl_cmd() {
  local verify_flag="-k"
  [[ "${SKIP_TLS_VERIFY:-1}" == "0" ]] && verify_flag=""
  local resolves=(
    "--resolve" "${HOSTNAME}:80:${TARGET_IP}"
    "--resolve" "${HOSTNAME}:443:${TARGET_IP}"
  )
  if [[ -n "${kc_host}" && "${kc_host}" != "${HOSTNAME}" ]]; then
    resolves+=("--resolve" "${kc_host}:80:${KC_TARGET_IP}" "--resolve" "${kc_host}:443:${KC_TARGET_IP}")
  fi
  curl -sS $verify_flag "${resolves[@]}" "$@"
}

check() {
  local url="$1"
  local label="$2"
  local expect_re="$3"
  code=$(curl_cmd -o /tmp/vps-check.tmp -w '%{http_code}' "$url" || true)
  if [[ "$code" =~ $expect_re ]]; then
    printf "[OK] %s (%s)\n" "$label" "$code"
  else
    printf "[XX] %s (got %s, expected %s)\n" "$label" "$code" "$expect_re"
    head -n 5 /tmp/vps-check.tmp | sed 's/^/   /'
    exit 1
  fi
}

echo "Checking via nginx at app=${HOSTNAME} (scheme=${SCHEME}, target_ip=${TARGET_IP})"
echo "Keycloak endpoint: ${KC_URL} (host=${kc_host}, target_ip=${KC_TARGET_IP})"

check "${SCHEME}://${HOSTNAME}/" "Homepage" "200"
check "${SCHEME}://${HOSTNAME}/accounts/login/" "Login page" "200"
check "${SCHEME}://${HOSTNAME}/accounts/login/keycloak/" "Keycloak login redirect" "30[12]"
check "${KC_URL}" "Keycloak OIDC config" "200"

echo "All VPS checks passed."
