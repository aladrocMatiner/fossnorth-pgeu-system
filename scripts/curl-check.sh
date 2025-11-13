#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
TMP_FILE="$(mktemp)"

echo "Testing endpoints against ${BASE_URL}"

curl_check() {
  local path="$1"
  local label="$2"
  local expected="$3"
  local url="${BASE_URL}${path}"
  echo "→ ${label}: ${url}"
  status="$(curl -sS -o "$TMP_FILE" -w "%{http_code}" "$url" || true)"
  if [[ "$expected" =~ $status ]]; then
    printf "   Status: %s (ok)\n" "$status"
  else
    printf "   Status: %s (expected %s)\n" "$status" "$expected"
    head -n 5 "$TMP_FILE" | sed 's/^/   /'
    echo
    echo "Test failed."
    exit 1
  fi
  head -n 5 "$TMP_FILE" | sed 's/^/   /'
  echo
}

curl_check "/" "Homepage" "200"
curl_check "/account/" "Account/login page" "200|302"
curl_check "/events/admin/" "Events admin (redirect expected)" "302|301"

rm -f "$TMP_FILE"

echo "All curl checks completed."
