#!/usr/bin/env bash
set -euo pipefail

read_secret_file() {
  local env_name="$1"
  local file_env_name="${env_name}_FILE"
  local value="${!env_name:-}"
  local file_value="${!file_env_name:-}"

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi

  if [[ -n "$file_value" && -f "$file_value" ]]; then
    tr -d '\r\n' < "$file_value"
    return 0
  fi

  return 1
}

if password="$(read_secret_file KEYCLOAK_ADMIN_PASSWORD)"; then
  export KEYCLOAK_ADMIN_PASSWORD="$password"
else
  echo "[keycloak-entrypoint] missing KEYCLOAK_ADMIN_PASSWORD or KEYCLOAK_ADMIN_PASSWORD_FILE" >&2
  exit 1
fi

if db_password="$(read_secret_file KC_DB_PASSWORD)"; then
  export KC_DB_PASSWORD="$db_password"
else
  echo "[keycloak-entrypoint] missing KC_DB_PASSWORD or KC_DB_PASSWORD_FILE" >&2
  exit 1
fi

exec /opt/keycloak/bin/kc.sh "$@"
