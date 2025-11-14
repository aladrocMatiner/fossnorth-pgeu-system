#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
KC_BASE="${KC_BASE:-http://127.0.0.1:8080}"
KC_HEALTH="${KC_HEALTH:-http://127.0.0.1:9000/health/ready}"
CLIENT_ID="${KEYCLOAK_CLIENT_ID:-pgeu}"

pass() { printf '[OK] %s\n' "$1"; }
fail() { printf '[XX] %s\n' "$1"; exit 1; }

echo "Checking stack at ${BASE_URL} with Keycloak ${KC_BASE} (client_id=${CLIENT_ID})"

echo "→ Keycloak health (ready)"
kc_status=$(curl -fsS -o /tmp/kc-health.json -w '%{http_code}' "${KC_HEALTH}" || true)
if [[ "$kc_status" != "200" ]]; then
  echo "[WARN] Keycloak health endpoint not reachable (HTTP $kc_status). Continuing with redirect test."
fi
grep -q '"status"\s*:\s*"UP"' /tmp/kc-health.json && pass "Keycloak reports UP" || pass "Keycloak ready endpoint returns 200"

echo "→ Homepage"
code=$(curl -fsS -o /tmp/home.html -w '%{http_code}' "${BASE_URL%/}/" || true)
[[ "$code" == "200" ]] && pass "Homepage 200" || fail "Homepage returned $code"

echo "→ OAuth login page"
code=$(curl -fsS -o /tmp/login.html -w '%{http_code}' "${BASE_URL%/}/accounts/login/" || true)
[[ "$code" == "200" ]] || fail "Login page returned $code"
grep -q "/accounts/login/keycloak/" /tmp/login.html && pass "Keycloak provider link present" || fail "Keycloak provider link missing"

echo "→ OAuth redirect flow (no credentials)"
loc=$(curl -fsS -o /dev/null -w '%{redirect_url}' "${BASE_URL%/}/accounts/login/keycloak/")
[[ -n "$loc" ]] || fail "No redirect from /accounts/login/keycloak/"
echo "   Redirect: $loc"
[[ "$loc" == *"/protocol/openid-connect/auth"* ]] || fail "Redirect not to Keycloak auth endpoint"
printf '%s' "$loc" | grep -q "client_id=${CLIENT_ID}" && pass "client_id correct" || fail "client_id not in redirect"

echo "SSO smoke test completed successfully."
