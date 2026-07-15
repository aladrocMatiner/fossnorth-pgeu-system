#!/usr/bin/env bash
# Common helpers for secret-safe validation scripts. Source this file.

vc_info() {
  printf '[-] %s\n' "$*"
}

vc_pass() {
  printf '[OK] %s\n' "$*"
}

vc_fail() {
  printf '[XX] %s\n' "$*" >&2
  VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
}

vc_die() {
  printf '[XX] %s\n' "$*" >&2
  exit 1
}

vc_bool_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

vc_require_cmd() {
  local cmd="$1"

  if command -v "$cmd" >/dev/null 2>&1; then
    vc_pass "command available: $cmd"
  else
    vc_fail "missing command: $cmd"
  fi
}

vc_require_file() {
  local path="$1"
  local label="$2"

  if [[ -f "$path" ]]; then
    vc_pass "$label"
  else
    vc_fail "$label (missing file: $path)"
  fi
}

vc_require_dir() {
  local path="$1"
  local label="$2"

  if [[ -d "$path" ]]; then
    vc_pass "$label"
  else
    vc_fail "$label (missing directory: $path)"
  fi
}

vc_require_executable() {
  local path="$1"
  local label="$2"

  if [[ -x "$path" ]]; then
    vc_pass "$label"
  elif [[ -f "$path" ]]; then
    vc_fail "$label (not executable: $path)"
  else
    vc_fail "$label (missing file: $path)"
  fi
}

vc_env_file_value() {
  local file="$1"
  local key="$2"

  [[ -f "$file" ]] || return 0

  awk -v key="$key" '
    /^[[:space:]]*#/ { next }
    $0 ~ "^[[:space:]]*" key "=" {
      sub("^[[:space:]]*" key "=", "", $0)
      sub("\r$", "", $0)
      print
      exit
    }
  ' "$file" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

vc_effective_env_value() {
  local file="$1"
  local key="$2"
  local value="${!key-}"

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi

  vc_env_file_value "$file" "$key"
}

vc_require_env_template_key() {
  local template="$1"
  local key="$2"

  if [[ ! -f "$template" ]]; then
    vc_fail "env template exists before checking $key"
    return
  fi

  if grep -Eq "^[[:space:]]*${key}=" "$template"; then
    vc_pass "env template key present: $key"
  else
    vc_fail "env template key missing: $key"
  fi
}

vc_redact_url() {
  local raw="${1:-}"

  if [[ -z "$raw" ]]; then
    printf '<empty>'
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$raw" <<'PY'
import sys
from urllib.parse import urlsplit, urlunsplit

raw = sys.argv[1]
try:
    parts = urlsplit(raw)
except ValueError:
    print("[redacted-url]")
    raise SystemExit(0)

netloc = parts.netloc.rsplit("@", 1)[-1]
query = "redacted=true" if parts.query else ""
fragment = "redacted" if parts.fragment else ""
print(urlunsplit((parts.scheme, netloc, parts.path, query, fragment)))
PY
  else
    raw="${raw%%#*}"
    if [[ "$raw" == *\?* ]]; then
      printf '%s?redacted=true' "${raw%%\?*}"
    else
      printf '%s' "$raw"
    fi
  fi
}

vc_url_host() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlsplit

parts = urlsplit(sys.argv[1])
print(parts.hostname or "")
PY
}

vc_url_port() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlsplit

parts = urlsplit(sys.argv[1])
if parts.port:
    print(parts.port)
elif parts.scheme == "https":
    print(443)
elif parts.scheme == "http":
    print(80)
else:
    print("")
PY
}

vc_url_join() {
  local base="${1%/}"
  local path="$2"

  if [[ "$path" != /* ]]; then
    path="/$path"
  fi

  printf '%s%s' "$base" "$path"
}
