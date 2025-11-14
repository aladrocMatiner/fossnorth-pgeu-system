#!/usr/bin/env bash
set -euo pipefail

# Simple non-interactive SSO login against local Keycloak and pgeu-system.
# Defaults are aligned with this compose stack.

BASE_URL="${BASE_URL:-http://localhost:8000}"
KC_REALM_BASE="${KC_REALM_BASE:-http://127.0.0.1:8080/realms/pgeu}"
USERNAME="${KEYCLOAK_USER:-fossnorth}"
PASSWORD="${KEYCLOAK_PASS:-fossnorth}"

JAR="$(mktemp)"
trap 'rm -f "$JAR" /tmp/sso-login-*.html /tmp/sso-login-*.hdr' EXIT

pass(){ printf '[OK] %s\n' "$1"; }
fail(){ printf '[XX] %s\n' "$1"; exit 1; }

echo "SSO login flow using BASE_URL=${BASE_URL} realm=${KC_REALM_BASE} user=${USERNAME}"

# 1) Kick off OAuth login to get redirect to Keycloak auth endpoint
echo "→ Initiate OAuth at ${BASE_URL}/accounts/login/keycloak/"
LOC=$(curl -sS -D /tmp/sso-login-1.hdr -o /dev/null -c "$JAR" -b "$JAR" "${BASE_URL%/}/accounts/login/keycloak/") || true
REDIR=$(awk 'BEGIN{IGNORECASE=1} /^Location:/{print $2}' /tmp/sso-login-1.hdr | tr -d '\r')
if [[ -z "$REDIR" ]]; then
  echo "Headers:"; sed -n '1,20p' /tmp/sso-login-1.hdr
  fail "No redirect from /accounts/login/keycloak/ (check web logs)"
fi
echo "   Redirect to: ${REDIR}"
[[ "$REDIR" == *"${KC_REALM_BASE}"* ]] || fail "Redirect does not point to expected realm"

# 2) Fetch Keycloak login page and extract form action
echo "→ Fetch Keycloak login page"
curl -sS -c "$JAR" -b "$JAR" -L "$REDIR" -o /tmp/sso-login-login.html
ACTION=$(python - <<'PY'
import re,sys
html=open('/tmp/sso-login-login.html','rb').read().decode('utf-8','ignore')
m=re.search(r'<form[^>]*id=[\"\']kc-form-login[\"\'][^>]*action=[\"\']([^\"\']+)[\"\']', html, re.I|re.S)
if not m:
    m=re.search(r'<form[^>]*action=[\"\']([^\"\']+)[\"\']', html, re.I|re.S)
print(m.group(1) if m else '')
PY
)
[[ -n "$ACTION" ]] || fail "Could not parse Keycloak login form action"
echo "   Form action: ${ACTION}"

# 3) Submit credentials to Keycloak
echo "→ Submit credentials"
curl -sS -c "$JAR" -b "$JAR" -D /tmp/sso-login-2.hdr -o /dev/null \
  -X POST "$ACTION" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "username=${USERNAME}" \
  --data-urlencode "password=${PASSWORD}" \
  --data-urlencode "credentialId=" || true

REDIR2=$(awk 'BEGIN{IGNORECASE=1} /^Location:/{print $2}' /tmp/sso-login-2.hdr | tr -d '\r')
[[ -n "$REDIR2" ]] || fail "No redirect after submitting credentials"
echo "   Redirect back to app: ${REDIR2}"

# 4) Follow redirect to app to complete token exchange and establish session
echo "→ Complete login at app"
curl -sS -c "$JAR" -b "$JAR" -L "$REDIR2" -o /tmp/sso-login-final.html >/dev/null

# 5) Verify authenticated access to /account/
echo "→ Verify access to /account/"
CODE=$(curl -sS -c "$JAR" -b "$JAR" -o /tmp/sso-login-account.html -w '%{http_code}' "${BASE_URL%/}/account/") || true
if [[ "$CODE" != "200" ]]; then
  echo "HTTP $CODE from /account/"; sed -n '1,40p' /tmp/sso-login-account.html
  fail "Did not get 200 on /account/, login may have failed"
fi
pass "Authenticated access confirmed."

echo "Done."
