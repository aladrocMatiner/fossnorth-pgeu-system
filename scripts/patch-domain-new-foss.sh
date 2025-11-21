#!/usr/bin/env bash
set -euo pipefail

APP_DOMAIN="${APP_DOMAIN:-new.foss-north.se}"
KEYCLOAK_DOMAIN="${KEYCLOAK_DOMAIN:-auth.foss-north.se}"
ENV_FILE="docker-compose/.env"
NGINX_CONF="docker-compose/nginx.conf"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi

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
    return
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

update_kv "DJANGO_SITE_BASE" "https://${APP_DOMAIN}"
update_kv "DJANGO_ALLOWED_HOSTS" "localhost,127.0.0.1,${APP_DOMAIN}"
update_kv "DJANGO_DISABLE_HTTPS_REDIRECTS" "false"
update_kv "DJANGO_SESSION_COOKIE_SECURE" "true"
update_kv "DJANGO_CSRF_COOKIE_SECURE" "true"
update_kv "DJANGO_ENABLE_OAUTH_AUTH" "true"

# Keycloak on dedicated host; keep verify off for self-signed tests
update_kv "KEYCLOAK_BASE_URL" "https://${KEYCLOAK_DOMAIN}/realms/pgeu"
update_kv "KEYCLOAK_CLIENT_ID" "pgeu"
update_kv "KEYCLOAK_SSL_VERIFY" "false"
update_kv "KEYCLOAK_PUBLIC_URL" "https://${KEYCLOAK_DOMAIN}/"

update_nginx_domains "${APP_DOMAIN}" "${KEYCLOAK_DOMAIN}"

./scripts/generate-keycloak-realm.sh

cat <<EOF
Patched configuration for app=${APP_DOMAIN}, keycloak=${KEYCLOAK_DOMAIN}.
- Updated ${ENV_FILE} (SITE_BASE, ALLOWED_HOSTS, KEYCLOAK_BASE_URL, secure cookies).
- Updated ${NGINX_CONF} server_name and cert references for both hosts.
Next steps:
  # Generate or place certs in certs/${APP_DOMAIN}.* and certs/${KEYCLOAK_DOMAIN}.*
  ./scripts/generate-selfsigned-cert.sh ${APP_DOMAIN}
  ./scripts/generate-selfsigned-cert.sh ${KEYCLOAK_DOMAIN}
  docker compose up -d nginx web          # restart to apply
EOF
