#!/usr/bin/env bash
set -euo pipefail

# One-shot setup for foss-north VPS/local environments.
# - Prepares docker-compose/.env with app + Keycloak hosts
# - Updates docker-compose/nginx.conf server blocks and cert paths
# - Regenerates Keycloak realm
# - Optionally generates self-signed certs for both hosts
#
# Defaults target:
#   APP domain: new.foss-north.se
#   Keycloak domain: auth.foss-north.se
# Override via environment (NON_INTERACTIVE=1 to skip prompts):
#   APP_DOMAIN=..., KEYCLOAK_DOMAIN=..., KEYCLOAK_SSL_VERIFY=true|false
#   GENERATE_CERTS=1|0 (default is to ask), NON_INTERACTIVE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/docker-compose/.env"
ENV_TEMPLATE="${ROOT_DIR}/docker-compose/.env.example"
NGINX_CONF="${ROOT_DIR}/docker-compose/nginx.conf"

default_app="${APP_DOMAIN:-new.foss-north.se}"
default_kc="${KEYCLOAK_DOMAIN:-auth.foss-north.se}"
default_verify="${KEYCLOAK_SSL_VERIFY:-true}"
default_generate="${GENERATE_CERTS:-ask}"
non_interactive="${NON_INTERACTIVE:-0}"

prompt() {
  local question="$1" default="$2" var
  if [[ "${non_interactive}" == "1" ]]; then
    echo "${default}"
    return
  fi
  read -r -p "${question} [${default}]: " var
  if [[ -z "${var}" ]]; then
    echo "${default}"
  else
    echo "${var}"
  fi
}

prompt_bool() {
  local question="$1" default="$2" var
  local def_disp
  [[ "${default,,}" == "true" || "${default}" == "1" ]] && def_disp="Y/n" || def_disp="y/N"
  if [[ "${non_interactive}" == "1" ]]; then
    echo "${default}"
    return
  fi
  read -r -p "${question} [${def_disp}]: " var
  var="${var:-${default}}"
  case "${var,,}" in
    y|yes|1|true) echo "true" ;;
    n|no|0|false) echo "false" ;;
    *) echo "${default}" ;;
  esac
}

update_kv() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >>"$ENV_FILE"
  fi
}

update_nginx_domains() {
  local app_domain="$1" kc_domain="$2"
  if [[ ! -f "$NGINX_CONF" ]]; then
    echo "nginx config not found: $NGINX_CONF" >&2
    return 1
  fi
  python - "$NGINX_CONF" "$app_domain" "$kc_domain" <<'PY'
import sys
from pathlib import Path

conf_path = Path(sys.argv[1])
app_domain = sys.argv[2]
kc_domain = sys.argv[3]

lines = conf_path.read_text().splitlines()
out = []
server_idx = cert_idx = key_idx = 0

for line in lines:
    stripped = line.strip()
    if stripped.startswith("server_name"):
        server_idx += 1
        indent = line[:line.index("server_name")]
        if server_idx == 1:
            line = f"{indent}server_name {app_domain} localhost _;"
        elif server_idx == 2:
            line = f"{indent}server_name {kc_domain};"
    if stripped.startswith("ssl_certificate "):
        cert_idx += 1
        indent = line[:line.index("ssl_certificate")]
        if cert_idx == 1:
            line = f"{indent}ssl_certificate     /etc/nginx/certs/{app_domain}.crt;"
        elif cert_idx == 2:
            line = f"{indent}ssl_certificate     /etc/nginx/certs/{kc_domain}.crt;"
    if stripped.startswith("ssl_certificate_key "):
        key_idx += 1
        indent = line[:line.index("ssl_certificate_key")]
        if key_idx == 1:
            line = f"{indent}ssl_certificate_key /etc/nginx/certs/{app_domain}.key;"
        elif key_idx == 2:
            line = f"{indent}ssl_certificate_key /etc/nginx/certs/{kc_domain}.key;"
    out.append(line)

conf_path.write_text("\n".join(out) + "\n")
PY
}

echo "=== foss-north setup ==="

if [[ ! -d "${ROOT_DIR}/pgeu-system" ]]; then
  echo "[WARN] Expected upstream repo at pgeu-system/ (clone it before running docker compose)."
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Creating ${ENV_FILE} from template..."
  cp "$ENV_TEMPLATE" "$ENV_FILE"
fi

APP_DOMAIN="$(prompt "App host (SITE_BASE)" "$default_app")"
KEYCLOAK_DOMAIN="$(prompt "Keycloak host" "$default_kc")"
VERIFY_TLS="$(prompt_bool "Verify Keycloak TLS (set false for self-signed)" "$default_verify")"

generate_choice="$default_generate"
if [[ "$default_generate" == "ask" ]]; then
  generate_choice="$(prompt_bool "Generate self-signed certs for both hosts" "false")"
fi

echo "Updating env..."
update_kv "DJANGO_SITE_BASE" "https://${APP_DOMAIN}"
update_kv "DJANGO_ALLOWED_HOSTS" "localhost,127.0.0.1,${APP_DOMAIN}"
update_kv "DJANGO_DISABLE_HTTPS_REDIRECTS" "false"
update_kv "DJANGO_SESSION_COOKIE_SECURE" "true"
update_kv "DJANGO_CSRF_COOKIE_SECURE" "true"
update_kv "DJANGO_ENABLE_OAUTH_AUTH" "true"
update_kv "KEYCLOAK_BASE_URL" "https://${KEYCLOAK_DOMAIN}/realms/pgeu"
update_kv "KEYCLOAK_CLIENT_ID" "pgeu"
update_kv "KEYCLOAK_SSL_VERIFY" "${VERIFY_TLS}"
update_kv "KEYCLOAK_PUBLIC_URL" "https://${KEYCLOAK_DOMAIN}/"

echo "Updating nginx server blocks..."
update_nginx_domains "${APP_DOMAIN}" "${KEYCLOAK_DOMAIN}"

echo "Regenerating Keycloak realm..."
"${ROOT_DIR}/scripts/generate-keycloak-realm.sh"

if [[ "${generate_choice,,}" == "true" || "${generate_choice}" == "1" ]]; then
  echo "Generating self-signed certificates..."
  "${ROOT_DIR}/scripts/generate-selfsigned-cert.sh" "${APP_DOMAIN}"
  "${ROOT_DIR}/scripts/generate-selfsigned-cert.sh" "${KEYCLOAK_DOMAIN}"
else
  echo "Skipping self-signed cert generation."
fi

cat <<EOF
Done.
- Env: ${ENV_FILE} (SITE_BASE=https://${APP_DOMAIN}, Keycloak=https://${KEYCLOAK_DOMAIN})
- nginx: ${NGINX_CONF} (server_name + certs updated)
- Realm: keycloak/realm-pgeu.json regenerated

Next:
  docker compose up -d --build
  docker compose up -d nginx web
  HOSTNAME_OVERRIDE=${APP_DOMAIN} KC_HOST_OVERRIDE=${KEYCLOAK_DOMAIN} ./scripts/vps-check.sh
EOF
