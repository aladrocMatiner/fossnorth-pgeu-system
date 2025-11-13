#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
TMP_FILE="$(mktemp)"

echo "Testing endpoints against ${BASE_URL}"

curl_check() {
  local path="$1"
  local label="$2"
  echo "→ ${label}: ${BASE_URL}${path}"
  curl -fsSL -o "$TMP_FILE" -w "Status: %{http_code}\n" "${BASE_URL}${path}"
  head -n 5 "$TMP_FILE" | sed 's/^/   /'
  echo
}

curl_check "/" "Homepage"
curl_check "/admin/login/" "Admin login"
curl_check "/account/" "User account"

rm -f "$TMP_FILE"

echo "All curl checks completed."
