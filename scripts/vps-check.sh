#!/usr/bin/env bash
set -euo pipefail

# Simple end-to-end check via nginx for a given host (defaults to foss-north.aladroc.io).
# Uses --resolve to point the hostname at TARGET_IP (default 127.0.0.1).

HOSTNAME="${HOSTNAME_OVERRIDE:-foss-north.aladroc.io}"
TARGET_IP="${TARGET_IP:-127.0.0.1}"

curl_cmd() {
  curl -ksS --resolve "${HOSTNAME}:80:${TARGET_IP}" --resolve "${HOSTNAME}:443:${TARGET_IP}" "$@"
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

echo "Checking via nginx at host=${HOSTNAME} target_ip=${TARGET_IP}"

check "http://${HOSTNAME}/" "HTTP homepage" "200"
check "https://${HOSTNAME}/" "HTTPS homepage" "200"
check "https://${HOSTNAME}/accounts/login/" "HTTPS login page" "200"
check "https://${HOSTNAME}/accounts/login/keycloak/" "Keycloak login redirect" "30[12]"
check "https://${HOSTNAME}/auth/realms/pgeu/.well-known/openid-configuration" "Keycloak OIDC config" "200"

echo "All VPS checks passed."
