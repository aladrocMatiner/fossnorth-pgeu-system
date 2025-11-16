#!/usr/bin/env bash
set -euo pipefail

DOMAIN="new.foss-north.se"
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

update_kv "DJANGO_SITE_BASE" "https://${DOMAIN}"
update_kv "DJANGO_ALLOWED_HOSTS" "localhost,127.0.0.1,${DOMAIN}"
update_kv "DJANGO_DISABLE_HTTPS_REDIRECTS" "false"
update_kv "DJANGO_SESSION_COOKIE_SECURE" "true"
update_kv "DJANGO_CSRF_COOKIE_SECURE" "true"
update_kv "DJANGO_ENABLE_OAUTH_AUTH" "true"
update_kv "KEYCLOAK_BASE_URL" "https://${DOMAIN}/auth/realms/pgeu"
update_kv "KEYCLOAK_CLIENT_ID" "pgeu"
# Test env with self-signed; disable verification
update_kv "KEYCLOAK_SSL_VERIFY" "false"
update_kv "KEYCLOAK_PUBLIC_URL" "https://${DOMAIN}/auth/"

if [[ -f "$NGINX_CONF" ]]; then
  sed -i "s|server_name .*|    server_name ${DOMAIN} localhost _;|" "$NGINX_CONF"
  sed -i "s|ssl_certificate\\s\\+.*|    ssl_certificate     /etc/nginx/certs/${DOMAIN}.crt;|" "$NGINX_CONF"
  sed -i "s|ssl_certificate_key\\s\\+.*|    ssl_certificate_key /etc/nginx/certs/${DOMAIN}.key;|" "$NGINX_CONF"
fi

./scripts/generate-keycloak-realm.sh

cat <<EOF
Patched configuration for ${DOMAIN}.
- Updated ${ENV_FILE} (SITE_BASE, ALLOWED_HOSTS, KEYCLOAK_BASE_URL, secure cookies).
- Updated ${NGINX_CONF} server_name and cert references.
Next steps:
  # Generate or place certs in certs/${DOMAIN}.crt|key
  ./scripts/generate-selfsigned-cert.sh   # edit script or rename files to match ${DOMAIN}
  docker compose up -d nginx web          # restart to apply
EOF
