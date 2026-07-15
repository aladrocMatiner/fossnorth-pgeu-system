#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
TEMPLATE_ARG=""
OUTPUT_ARG=""

usage() {
  cat <<'USAGE'
Usage: scripts/generate-keycloak-realm.sh [--env-file PATH] [--template PATH] [--output PATH]

Generates the ignored Keycloak realm import JSON for PGEU SSO.

Required secret input:
  PGEU_KEYCLOAK_CLIENT_SECRET_FILE or KEYCLOAK_CLIENT_SECRET_FILE

The script never prints the secret value.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --template)
      TEMPLATE_ARG="$2"
      shift 2
      ;;
    --output)
      OUTPUT_ARG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

normalize_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s' "$path"
  else
    printf '%s/%s' "$ROOT_DIR" "${path#./}"
  fi
}

load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0

  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    case "$key" in
      \#*) continue ;;
    esac
    key="${key%%[[:space:]]*}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    value="${value%$'\r'}"
    value="${value%\"}"
    value="${value#\"}"
    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$env_file"
}

read_secret() {
  local name="$1"
  local file_name="${name}_FILE"
  local direct="${!name:-}"
  local file_value="${!file_name:-}"

  if [[ -n "$direct" ]]; then
    printf '%s' "$direct"
    return 0
  fi

  if [[ -n "$file_value" ]]; then
    file_value="$(normalize_path "$file_value")"
    if [[ -f "$file_value" ]]; then
      tr -d '\r\n' < "$file_value"
      return 0
    fi
  fi

  return 1
}

normalize_url() {
  local value="$1"
  value="${value%/}"
  if [[ ! "$value" =~ ^https?:// ]]; then
    echo "URL must start with http:// or https://: $value" >&2
    exit 1
  fi
  printf '%s' "$value"
}

load_env_file "$(normalize_path "$ENV_FILE")"

: "${KEYCLOAK_REALM:=pgeu}"
: "${KEYCLOAK_CLIENT_ID:=${PGEU_KEYCLOAK_CLIENT_ID:-pgeu}}"
: "${PGEU_SITE_BASE:=https://${PGEU_HOST:-pgeu.localhost}}"

TEMPLATE="$(normalize_path "${TEMPLATE_ARG:-${KEYCLOAK_REALM_TEMPLATE:-services/keycloak/realm-pgeu.tmpl.json}}")"
OUTPUT_FILE="$(normalize_path "${OUTPUT_ARG:-${KEYCLOAK_REALM_IMPORT_FILE:-${KEYCLOAK_IMPORT_DIR:-runtime/keycloak/import}/realm-pgeu.json}}")"
PGEU_SITE_BASE="$(normalize_url "$PGEU_SITE_BASE")"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template not found: $TEMPLATE" >&2
  exit 1
fi

if ! client_secret="$(read_secret PGEU_KEYCLOAK_CLIENT_SECRET)"; then
  if ! client_secret="$(read_secret KEYCLOAK_CLIENT_SECRET)"; then
    echo "Missing PGEU_KEYCLOAK_CLIENT_SECRET_FILE or KEYCLOAK_CLIENT_SECRET_FILE." >&2
    exit 1
  fi
fi

case "$OUTPUT_FILE" in
  "$ROOT_DIR"/services/keycloak/generated/*|"$ROOT_DIR"/runtime/*)
    ;;
  *)
    echo "Refusing to write secret-bearing realm outside an ignored generated/runtime path: $OUTPUT_FILE" >&2
    exit 1
    ;;
esac

export KEYCLOAK_REALM KEYCLOAK_CLIENT_ID KEYCLOAK_CLIENT_SECRET="$client_secret" PGEU_SITE_BASE

mkdir -p "$(dirname "$OUTPUT_FILE")"
umask 077

python3 - "$TEMPLATE" "$OUTPUT_FILE" <<'PY'
import json
import os
import string
import sys
from pathlib import Path

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

rendered = string.Template(template_path.read_text(encoding="utf-8")).substitute(os.environ)
json.loads(rendered)
output_path.write_text(rendered + "\n", encoding="utf-8")
PY

chmod 0600 "$OUTPUT_FILE"
echo "Generated $OUTPUT_FILE"
echo "Realm: $KEYCLOAK_REALM"
echo "Client: $KEYCLOAK_CLIENT_ID"
echo "PGEU site base: $PGEU_SITE_BASE"
echo "Client secret: included"
