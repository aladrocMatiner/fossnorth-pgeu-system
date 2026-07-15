#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-.env}"
CACERT=""
TARGET_IP=""
HOST_RESOLVE=""

usage() {
  cat <<'USAGE'
Usage: scripts/check-keycloak-oidc.sh [--env-file PATH] [--cacert PATH] [--target-ip IP] [--resolve VALUE]

Checks Keycloak OIDC discovery through the public Traefik hostname without
printing credentials, cookies, tokens, or client secrets.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --cacert)
      CACERT="$2"
      shift 2
      ;;
    --target-ip)
      TARGET_IP="$2"
      shift 2
      ;;
    --resolve)
      if [[ -n "$HOST_RESOLVE" ]]; then
        HOST_RESOLVE="${HOST_RESOLVE},$2"
      else
        HOST_RESOLVE="$2"
      fi
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

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

read_env_value() {
  local key="$1"
  local current="${!key-}"

  if [[ -n "$current" ]]; then
    printf '%s' "$current"
    return
  fi

  if [[ ! -f "$ENV_FILE" ]]; then
    return
  fi

  awk -v key="$key" '
    /^[[:space:]]*#/ { next }
    $0 ~ "^[[:space:]]*" key "=" {
      sub("^[[:space:]]*" key "=", "", $0)
      sub("\r$", "", $0)
      print
      exit
    }
  ' "$ENV_FILE" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

require_tool curl
require_tool jq

keycloak_host="$(read_env_value KEYCLOAK_HOST)"
keycloak_realm="$(read_env_value KEYCLOAK_REALM)"
stepca_root_cert="$(read_env_value STEPCA_ROOT_CERT)"

keycloak_realm="${keycloak_realm:-pgeu}"
CACERT="${CACERT:-$stepca_root_cert}"

if [[ -z "$keycloak_host" ]]; then
  echo "KEYCLOAK_HOST is required." >&2
  exit 1
fi

url="https://${keycloak_host}/realms/${keycloak_realm}/.well-known/openid-configuration"
expected_issuer="https://${keycloak_host}/realms/${keycloak_realm}"

curl_args=(-fsS)
if [[ -n "$CACERT" ]]; then
  curl_args+=(--cacert "$CACERT")
fi

if [[ -n "$TARGET_IP" ]]; then
  curl_args+=(--resolve "${keycloak_host}:443:${TARGET_IP}")
fi

if [[ -n "$HOST_RESOLVE" ]]; then
  resolve_values="${HOST_RESOLVE//,/ }"
  for resolve_value in $resolve_values; do
    curl_args+=(--resolve "$resolve_value")
  done
fi

document="$(curl "${curl_args[@]}" "$url")"
issuer="$(jq -r '.issuer // empty' <<<"$document")"
authorization_endpoint="$(jq -r '.authorization_endpoint // empty' <<<"$document")"
token_endpoint="$(jq -r '.token_endpoint // empty' <<<"$document")"

if [[ "$issuer" != "$expected_issuer" ]]; then
  echo "Unexpected issuer. Expected $expected_issuer, got ${issuer:-<empty>}." >&2
  exit 1
fi

if [[ -z "$authorization_endpoint" || -z "$token_endpoint" ]]; then
  echo "OIDC discovery is missing required endpoint metadata." >&2
  exit 1
fi

echo "OIDC discovery OK: $issuer"
