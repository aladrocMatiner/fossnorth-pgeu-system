#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/app
LOCAL_SETTINGS_FILE="${APP_DIR}/postgresqleu/local_settings.py"

bool_to_py() {
  local value="${1:-}"
  local default="${2:-False}"
  if [[ -z "${value}" ]]; then
    echo "${default}"
    return
  fi
  case "${value,,}" in
    1|true|yes|on) echo "True" ;;
    0|false|no|off) echo "False" ;;
    *) echo "${default}" ;;
  esac
}

# Generate random secret if none provided
if [[ -z "${DJANGO_SECRET_KEY:-}" ]]; then
  DJANGO_SECRET_KEY="$(python - <<'PY'
import secrets
print(secrets.token_urlsafe(50))
PY
)"
fi

allowed_hosts_py="$(python - <<'PY'
import os, json
hosts = os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")
items = [h.strip() for h in hosts.split(",") if h.strip()]
if not items:
    items = ["localhost"]
print(json.dumps(items))
PY
)"

debug_flag="$(bool_to_py "${DJANGO_DEBUG:-}" "False")"
redirect_flag="$(bool_to_py "${DJANGO_DISABLE_HTTPS_REDIRECTS:-}" "False")"
session_secure_flag="$(bool_to_py "${DJANGO_SESSION_COOKIE_SECURE:-}" "False")"
csrf_secure_flag="$(bool_to_py "${DJANGO_CSRF_COOKIE_SECURE:-}" "False")"
auto_migrate_flag="$(bool_to_py "${DJANGO_AUTO_MIGRATE:-True}" "True")"
auto_collectstatic_flag="$(bool_to_py "${DJANGO_AUTO_COLLECTSTATIC:-True}" "True")"

DB_NAME="${DJANGO_DB_NAME:-${POSTGRES_DB:-pgeu}}"
DB_USER="${DJANGO_DB_USER:-${POSTGRES_USER:-pgeu}}"
DB_PASSWORD="${DJANGO_DB_PASSWORD:-${POSTGRES_PASSWORD:-pgeu}}"
DB_HOST="${DJANGO_DB_HOST:-db}"
DB_PORT="${DJANGO_DB_PORT:-5432}"

# Normalize SITE BASE (strip trailing slash)
SITE_BASE="${DJANGO_SITE_BASE:-http://localhost:8000/}"
SITE_BASE="${SITE_BASE%/}"
SERVER_EMAIL="${DJANGO_SERVER_EMAIL:-noreply@example.org}"

# Optional OAuth/Keycloak config
ENABLE_OAUTH_AUTH="$(bool_to_py "${DJANGO_ENABLE_OAUTH_AUTH:-False}" "False")"
KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-}"
KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-}"

mkdir -p "${APP_DIR}/media" "${APP_DIR}/staticfiles"

cat > "${LOCAL_SETTINGS_FILE}" <<EOF
import os

DEBUG = ${debug_flag}
DISABLE_HTTPS_REDIRECTS = ${redirect_flag}
ALLOWED_HOSTS = ${allowed_hosts_py}
SECRET_KEY = "${DJANGO_SECRET_KEY}"
SERVER_EMAIL = "${SERVER_EMAIL}"
SITEBASE = "${SITE_BASE}"
SESSION_COOKIE_SECURE = ${session_secure_flag}
CSRF_COOKIE_SECURE = ${csrf_secure_flag}

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql_psycopg2",
        "NAME": "${DB_NAME}",
        "HOST": "${DB_HOST}",
        "PORT": "${DB_PORT}",
        "USER": "${DB_USER}",
        "PASSWORD": "${DB_PASSWORD}",
    }
}

STATIC_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../staticfiles")
MEDIA_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../media")
EOF

cd "${APP_DIR}"

# Optionally append OAuth/Keycloak settings
if [[ "${ENABLE_OAUTH_AUTH}" == "True" ]]; then
  if [[ -n "${KEYCLOAK_BASE_URL}" && -n "${KEYCLOAK_CLIENT_ID}" ]]; then
    cat >> "${LOCAL_SETTINGS_FILE}" <<EOF

ENABLE_OAUTH_AUTH = True
OAUTH = {
    'keycloak': {
        'clientid': '${KEYCLOAK_CLIENT_ID}',
        'secret': '${KEYCLOAK_CLIENT_SECRET}',
        'baseurl': '${KEYCLOAK_BASE_URL}',
    }
}
EOF
  else
    echo "[entrypoint] OAuth enabled but KEYCLOAK_BASE_URL/KEYCLOAK_CLIENT_ID missing; skipping OAUTH config" >&2
  fi
fi

if [[ "${auto_migrate_flag}" == "True" ]]; then
  # If OAuth is enabled, wait for OIDC discovery to be available (Keycloak ready)
  if [[ "${ENABLE_OAUTH_AUTH}" == "True" && -n "${KEYCLOAK_BASE_URL}" ]]; then
    echo "[entrypoint] Waiting for OIDC discovery at provider..."
    python - <<'PY'
import os, sys, time, urllib.request
base = os.environ.get('KEYCLOAK_BASE_URL','').rstrip('/')
if base:
    url = f"{base}/.well-known/openid-configuration"
    for i in range(60):
        try:
            with urllib.request.urlopen(url, timeout=3) as r:
                if r.status == 200:
                    print("[entrypoint] OIDC discovery available")
                    break
        except Exception as e:
            pass
        time.sleep(2)
PY
  fi
  python manage.py migrate --noinput
fi

if [[ "${auto_collectstatic_flag}" == "True" ]]; then
  python manage.py collectstatic --noinput
fi

exec "$@"
