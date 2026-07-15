#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${PGEU_APP_DIR:-/app}"
REQUIREMENTS_FILE="${PGEU_REQUIREMENTS_FILE:-${APP_DIR}/tools/devsetup/dev_requirements.txt}"
MANAGE_PY="${APP_DIR}/manage.py"
BOOTSTRAP_PIP_PACKAGES="${PGEU_BOOTSTRAP_PIP_PACKAGES:-setuptools<81 wheel}"

bool_enabled() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

die() {
  printf '[pgeu-entrypoint] %s\n' "$1" >&2
  exit 1
}

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local label="$3"
  local attempts="${4:-60}"

  printf '[pgeu-entrypoint] waiting for %s at %s:%s\n' "$label" "$host" "$port"
  for _ in $(seq 1 "$attempts"); do
    if nc -z "$host" "$port" >/dev/null 2>&1; then
      printf '[pgeu-entrypoint] %s is reachable\n' "$label"
      return 0
    fi
    sleep 2
  done

  die "$label was not reachable before timeout"
}

ensure_venv() {
  local venv="${VIRTUAL_ENV:-/opt/pgeu/venv}"
  if [[ ! -x "${venv}/bin/python" ]]; then
    printf '[pgeu-entrypoint] initializing Python virtualenv at %s\n' "$venv"
    python3 -m venv "$venv"
    "${venv}/bin/python" -m pip install --upgrade pip setuptools wheel
  fi
  export VIRTUAL_ENV="$venv"
  export PATH="${venv}/bin:${PATH}"
}

[[ -d "$APP_DIR" ]] || die "PGEU_APP_DIR does not exist: $APP_DIR"
[[ -f "$MANAGE_PY" ]] || die "missing manage.py in PGEU_APP_DIR: $APP_DIR"
[[ -f "$APP_DIR/postgresqleu/settings.py" ]] || die "missing postgresqleu/settings.py in PGEU_APP_DIR"

if [[ -n "${PGEU_TRUST_BUNDLE_PATH:-}" && -f "${PGEU_TRUST_BUNDLE_PATH}" ]]; then
  system_ca_bundle="${PGEU_SYSTEM_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
  if [[ -f "$system_ca_bundle" ]]; then
    combined_ca_bundle="${PGEU_COMBINED_CA_BUNDLE:-/tmp/pgeu-ca-bundle.crt}"
    cat "$system_ca_bundle" "${PGEU_TRUST_BUNDLE_PATH}" > "$combined_ca_bundle"
    export REQUESTS_CA_BUNDLE="$combined_ca_bundle"
    export SSL_CERT_FILE="$combined_ca_bundle"
  else
    export REQUESTS_CA_BUNDLE="${PGEU_TRUST_BUNDLE_PATH}"
    export SSL_CERT_FILE="${PGEU_TRUST_BUNDLE_PATH}"
  fi
fi

pgeu-render-local-settings
ensure_venv

if [[ -n "$BOOTSTRAP_PIP_PACKAGES" ]]; then
  printf '[pgeu-entrypoint] ensuring Python bootstrap packages\n'
  # shellcheck disable=SC2086
  python -m pip install --upgrade $BOOTSTRAP_PIP_PACKAGES
fi

if bool_enabled "${PGEU_INSTALL_REQUIREMENTS:-true}"; then
  [[ -f "$REQUIREMENTS_FILE" ]] || die "requirements file not found: $REQUIREMENTS_FILE"
  printf '[pgeu-entrypoint] installing Python requirements from %s\n' "$REQUIREMENTS_FILE"
  python -m pip install -r "$REQUIREMENTS_FILE"
fi

if bool_enabled "${PGEU_WAIT_FOR_DB:-true}"; then
  wait_for_tcp "${PGEU_DB_HOST:-pgeu-db}" "${PGEU_DB_PORT:-5432}" "PGEU database" "${PGEU_DB_WAIT_ATTEMPTS:-60}"
fi

cd "$APP_DIR"

if bool_enabled "${PGEU_AUTO_MIGRATE:-true}"; then
  printf '[pgeu-entrypoint] running migrations\n'
  python manage.py migrate --noinput
fi

if bool_enabled "${PGEU_AUTO_COLLECTSTATIC:-true}"; then
  printf '[pgeu-entrypoint] collecting static files\n'
  python manage.py collectstatic --noinput
fi

exec "$@"
