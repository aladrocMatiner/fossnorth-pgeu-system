#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/validation-common.sh
. "${SCRIPT_DIR}/validation-common.sh"

cd "$REPO_ROOT"

VALIDATION_FAILURES=0
ENV_FILE="${PGEU_STACK_ENV_FILE:-.env}"
PGEU_URL=""
KEYCLOAK_REALM_URL=""
CA_ROOT=""
TLS_VERIFY="${PGEU_ROLE_SMOKE_TLS_VERIFY:-true}"
HOST_RESOLVE="${PGEU_ROLE_SMOKE_RESOLVE:-}"
TARGET_IP="${PGEU_ROLE_SMOKE_TARGET_IP:-}"
CONNECT_TIMEOUT="${PGEU_ROLE_SMOKE_CONNECT_TIMEOUT:-5}"
MAX_TIME="${PGEU_ROLE_SMOKE_MAX_TIME:-30}"
CHECK_REVOCATION="true"
MANAGE_KEYCLOAK_ROLES="${PGEU_ROLE_SMOKE_MANAGE_KEYCLOAK_ROLES:-true}"

usage() {
  cat <<'USAGE'
Usage: scripts/smoke-keycloak-role-sync.sh [options]

Runs credentialed, secret-safe role-sync checks for the PGEU Keycloak integration.

Options:
  --env-file PATH        Runtime env file. Default: .env
  --pgeu-url URL         PGEU public base URL.
  --keycloak-url URL     Keycloak realm base URL.
  --ca-root PATH         CA root certificate path for TLS verification.
  --resolve VALUE        curl --resolve value. Repeatable.
  --target-ip IP         Resolve PGEU and Keycloak URL hosts to this IP.
  --insecure             Disable TLS verification for this run.
  --skip-revocation      Skip the manager-role removal/restoration check.
  --skip-role-management Do not update Keycloak roles before checks; requires
                         roles to be pre-normalized and implies no revocation.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --pgeu-url)
      PGEU_URL="$2"
      shift 2
      ;;
    --keycloak-url)
      KEYCLOAK_REALM_URL="$2"
      shift 2
      ;;
    --ca-root)
      CA_ROOT="$2"
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
    --target-ip)
      TARGET_IP="$2"
      shift 2
      ;;
    --insecure)
      TLS_VERIFY="false"
      shift
      ;;
    --skip-revocation)
      CHECK_REVOCATION="false"
      shift
      ;;
    --skip-role-management)
      MANAGE_KEYCLOAK_ROLES="false"
      CHECK_REVOCATION="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      vc_die "unknown argument: $1"
      ;;
  esac
done

if ! vc_bool_true "$MANAGE_KEYCLOAK_ROLES" && vc_bool_true "$CHECK_REVOCATION"; then
  vc_die "--skip-role-management requires --skip-revocation"
fi

env_default() {
  local key="$1"
  local fallback="$2"
  local value

  value="$(vc_effective_env_value "$ENV_FILE" "$key")"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi

  value="$(vc_env_file_value ".env.example" "$key")"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi

  printf '%s' "$fallback"
}

first_header() {
  local header_file="$1"
  local name="$2"

  awk -v name="$name" '
    BEGIN { expected = tolower(name) ":" }
    tolower(substr($0, 1, length(expected))) == expected {
      sub("^[^:]+:[[:space:]]*", "", $0)
      sub("\r$", "", $0)
      print
      exit
    }
  ' "$header_file"
}

keycloak_host="$(env_default KEYCLOAK_HOST keycloak.localhost)"
keycloak_realm="$(env_default KEYCLOAK_REALM pgeu)"
pgeu_host="$(env_default PGEU_HOST pgeu.localhost)"

PGEU_URL="${PGEU_URL:-${PGEU_ROLE_SMOKE_PGEU_URL:-$(env_default PGEU_SITE_BASE "https://${pgeu_host}")}}"
KEYCLOAK_REALM_URL="${KEYCLOAK_REALM_URL:-${PGEU_ROLE_SMOKE_KEYCLOAK_REALM_URL:-$(env_default PGEU_KEYCLOAK_BASE_URL "https://${keycloak_host}/realms/${keycloak_realm}")}}"
CA_ROOT="${CA_ROOT:-${PGEU_ROLE_SMOKE_CA_ROOT:-$(env_default STEPCA_ROOT_CERT "runtime/certs/stepca/root_ca.crt")}}"
CLIENT_ID="$(env_default PGEU_KEYCLOAK_CLIENT_ID pgeu)"
PGEU_LOGIN_URL="$(vc_url_join "$PGEU_URL" /accounts/login/keycloak/)"

normal_user="$(env_default KEYCLOAK_VALIDATION_USER pgeu-test)"
normal_email="$(env_default KEYCLOAK_VALIDATION_EMAIL "${normal_user}@${pgeu_host}")"
normal_password_file="$(env_default KEYCLOAK_VALIDATION_PASSWORD_FILE ./runtime/secrets/keycloak-pgeu-test-password)"

manager_user="$(env_default KEYCLOAK_VALIDATION_MANAGER_USER pgeu-manager)"
manager_email="$(env_default KEYCLOAK_VALIDATION_MANAGER_EMAIL "${manager_user}@${pgeu_host}")"
manager_password_file="$(env_default KEYCLOAK_VALIDATION_MANAGER_PASSWORD_FILE ./runtime/secrets/keycloak-pgeu-manager-password)"

news_user="$(env_default KEYCLOAK_VALIDATION_NEWS_USER pgeu-news)"
news_email="$(env_default KEYCLOAK_VALIDATION_NEWS_EMAIL "${news_user}@${pgeu_host}")"
news_password_file="$(env_default KEYCLOAK_VALIDATION_NEWS_PASSWORD_FILE ./runtime/secrets/keycloak-pgeu-news-password)"

membership_user="$(env_default KEYCLOAK_VALIDATION_MEMBERSHIP_USER pgeu-membership)"
membership_email="$(env_default KEYCLOAK_VALIDATION_MEMBERSHIP_EMAIL "${membership_user}@${pgeu_host}")"
membership_password_file="$(env_default KEYCLOAK_VALIDATION_MEMBERSHIP_PASSWORD_FILE ./runtime/secrets/keycloak-pgeu-membership-password)"

election_user="$(env_default KEYCLOAK_VALIDATION_ELECTION_USER pgeu-election)"
election_email="$(env_default KEYCLOAK_VALIDATION_ELECTION_EMAIL "${election_user}@${pgeu_host}")"
election_password_file="$(env_default KEYCLOAK_VALIDATION_ELECTION_PASSWORD_FILE ./runtime/secrets/keycloak-pgeu-election-password)"

accounting_user="$(env_default KEYCLOAK_VALIDATION_ACCOUNTING_USER pgeu-accounting)"
accounting_email="$(env_default KEYCLOAK_VALIDATION_ACCOUNTING_EMAIL "${accounting_user}@${pgeu_host}")"
accounting_password_file="$(env_default KEYCLOAK_VALIDATION_ACCOUNTING_PASSWORD_FILE ./runtime/secrets/keycloak-pgeu-accounting-password)"

superadmin_user="$(env_default KEYCLOAK_VALIDATION_SUPERADMIN_USER pgeu-superadmin)"
superadmin_email="$(env_default KEYCLOAK_VALIDATION_SUPERADMIN_EMAIL "${superadmin_user}@${pgeu_host}")"
superadmin_password_file="$(env_default KEYCLOAK_VALIDATION_SUPERADMIN_PASSWORD_FILE ./runtime/secrets/keycloak-pgeu-superadmin-password)"

role_cases=(
  "invoice manager|${manager_user}|${manager_email}|${manager_password_file}|pgeu-user,pgeu-invoice-manager|Invoice managers|/invoiceadmin/|Invoices"
  "news administrator|${news_user}|${news_email}|${news_password_file}|pgeu-user,pgeu-news-admin|News administrators|/admin/news/news/|News"
  "membership administrator|${membership_user}|${membership_email}|${membership_password_file}|pgeu-user,pgeu-membership-admin|Membership administrators|/admin/membership/members/|Membership"
  "election administrator|${election_user}|${election_email}|${election_password_file}|pgeu-user,pgeu-election-admin|Election administrators|/admin/elections/election/|Elections"
  "accounting manager|${accounting_user}|${accounting_email}|${accounting_password_file}|pgeu-user,pgeu-accounting-manager|Accounting managers|/admin/accounting/accountstructure/|Accounting"
)

curl_args=(
  --silent
  --show-error
  --connect-timeout "$CONNECT_TIMEOUT"
  --max-time "$MAX_TIME"
)

if vc_bool_true "$TLS_VERIFY"; then
  if [[ -f "$CA_ROOT" ]]; then
    curl_args+=(--cacert "$CA_ROOT")
  else
    vc_fail "CA root certificate file exists for role smoke TLS verification"
  fi
else
  curl_args+=(--insecure)
  vc_info "TLS verification disabled for role smoke test"
fi

add_resolve() {
  local value="$1"
  [[ -n "$value" ]] || return
  curl_args+=(--resolve "$value")
}

if [[ -n "$TARGET_IP" ]]; then
  for url in "$PGEU_URL" "$KEYCLOAK_REALM_URL"; do
    host="$(vc_url_host "$url")"
    if [[ -n "$host" ]]; then
      add_resolve "${host}:80:${TARGET_IP}"
      add_resolve "${host}:443:${TARGET_IP}"
    fi
  done
fi

if [[ -n "$HOST_RESOLVE" ]]; then
  resolve_values="${HOST_RESOLVE//,/ }"
  for resolve_value in $resolve_values; do
    add_resolve "$resolve_value"
  done
fi

extract_login_action() {
  local html_file="$1"
  local page_url="$2"

  python3 - "$html_file" "$page_url" <<'PY'
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin

class FormParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.actions = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "form":
            return
        data = dict(attrs)
        action = data.get("action")
        if not action:
            return
        form_id = data.get("id", "")
        if form_id == "kc-form-login":
            self.actions.insert(0, action)
        else:
            self.actions.append(action)

parser = FormParser()
with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as handle:
    parser.feed(handle.read())

if not parser.actions:
    raise SystemExit("Keycloak login form action not found")

print(urljoin(sys.argv[2], parser.actions[0]))
PY
}

set_keycloak_user_roles() {
  local username="$1"
  local roles_csv="$2"

  if ! vc_bool_true "$MANAGE_KEYCLOAK_ROLES"; then
    vc_info "using pre-normalized Keycloak roles for ${username}"
    return
  fi

  docker compose exec -T \
    -e PGEU_KEYCLOAK_REALM="$keycloak_realm" \
    -e PGEU_KEYCLOAK_CLIENT_ID="$CLIENT_ID" \
    -e PGEU_VALIDATION_USERNAME="$username" \
    -e PGEU_VALIDATION_ROLES="$roles_csv" \
    keycloak bash -lc '
set -euo pipefail
admin_password="$(tr -d "\r\n" < /run/secrets/keycloak_admin_password)"
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://127.0.0.1:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN" \
  --password "$admin_password" >/dev/null

all_roles=(
  pgeu-user
  pgeu-superadmin
  pgeu-invoice-manager
  pgeu-news-admin
  pgeu-membership-admin
  pgeu-election-admin
  pgeu-accounting-manager
  pgeu-series-admin
  pgeu-conference-admin
  pgeu-conference-tester
  pgeu-conference-talkvoter
  pgeu-conference-staff
  pgeu-conference-volunteer
  pgeu-conference-checkin-processor
  pgeu-sponsor-manager
  pgeu-sponsor-badge-scanner
  pgeu-meeting-admin
  pgeu-wiki-viewer
  pgeu-wiki-editor
)
IFS=, read -r -a desired_roles <<< "$PGEU_VALIDATION_ROLES"
for role_name in "${all_roles[@]}"; do
  remove_role=true
  for desired_role in "${desired_roles[@]}"; do
    if [[ "$role_name" == "$desired_role" ]]; then
      remove_role=false
      break
    fi
  done

  if [[ "$remove_role" == "true" ]]; then
    /opt/keycloak/bin/kcadm.sh remove-roles \
      -r "$PGEU_KEYCLOAK_REALM" \
      --uusername "$PGEU_VALIDATION_USERNAME" \
      --cclientid "$PGEU_KEYCLOAK_CLIENT_ID" \
      --rolename "$role_name" >/dev/null 2>&1 || true
  else
    /opt/keycloak/bin/kcadm.sh add-roles \
      -r "$PGEU_KEYCLOAK_REALM" \
      --uusername "$PGEU_VALIDATION_USERNAME" \
      --cclientid "$PGEU_KEYCLOAK_CLIENT_ID" \
      --rolename "$role_name" >/dev/null 2>&1 || true
  fi
done
' </dev/null
}

browser_login() {
  local username="$1"
  local password_file="$2"
  local label="$3"
  local cookie_file="${4:-${tmp_dir}/${username}.cookies}"
  local headers_file="${tmp_dir}/${username}.headers"
  local body_file="${tmp_dir}/${username}.body"
  local password_tmp="${tmp_dir}/${username}.password"
  local status
  local location
  local action

  if [[ ! -s "$password_file" ]]; then
    vc_fail "${label} password file exists"
    return
  fi

  tr -d "\r\n" < "$password_file" > "$password_tmp"
  chmod 0600 "$password_tmp"
  rm -f "$cookie_file"

  status="$(curl "${curl_args[@]}" --cookie-jar "$cookie_file" --dump-header "$headers_file" --output "$body_file" --write-out '%{http_code}' "$PGEU_LOGIN_URL" || true)"
  if [[ ! "$status" =~ ^30[12378]$ ]]; then
    vc_fail "${label} PGEU login starts OIDC redirect; status=${status:-000}"
    return
  fi

  location="$(first_header "$headers_file" Location)"
  if [[ -z "$location" ]]; then
    vc_fail "${label} PGEU login redirect includes Location"
    return
  fi

  status="$(curl "${curl_args[@]}" --cookie "$cookie_file" --cookie-jar "$cookie_file" --dump-header "$headers_file" --output "$body_file" --write-out '%{http_code}' "$location" || true)"
  if [[ "$status" != "200" ]]; then
    vc_fail "${label} Keycloak login form loads; status=${status:-000}; url=$(vc_redact_url "$location")"
    return
  fi

  if ! action="$(extract_login_action "$body_file" "$location" 2>"${tmp_dir}/${username}.action.err")"; then
    vc_fail "${label} Keycloak login form action parsed ($(cat "${tmp_dir}/${username}.action.err"))"
    return
  fi

  status="$(
    curl "${curl_args[@]}" \
      --cookie "$cookie_file" \
      --cookie-jar "$cookie_file" \
      --location \
      --dump-header "$headers_file" \
      --output "$body_file" \
      --write-out '%{http_code}' \
      --data-urlencode "username=${username}" \
      --data-urlencode "password@${password_tmp}" \
      --data-urlencode "credentialId=" \
      "$action" || true
  )"

  if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
    vc_pass "${label} browser login completed through PGEU and Keycloak"
  else
    vc_fail "${label} browser login completed through PGEU and Keycloak; status=${status:-000}"
  fi
}

assert_django_user() {
  local email="$1"
  local expected_staff="$2"
  local expected_superuser="$3"
  local expected_groups="$4"
  local label="$5"
  local output_file="${tmp_dir}/${label//[^A-Za-z0-9_.-]/_}.django"

  if docker compose exec -T \
      -e EXPECTED_EMAIL="$email" \
      -e EXPECTED_STAFF="$expected_staff" \
      -e EXPECTED_SUPERUSER="$expected_superuser" \
      -e EXPECTED_GROUPS="$expected_groups" \
      pgeu-web python manage.py shell <<'PY' >"$output_file" 2>&1
import os
import sys
from django.contrib.auth.models import User

email = os.environ["EXPECTED_EMAIL"]
expected_staff = os.environ["EXPECTED_STAFF"] == "true"
expected_superuser = os.environ["EXPECTED_SUPERUSER"] == "true"
expected_groups = set(filter(None, os.environ["EXPECTED_GROUPS"].split(",")))

try:
    user = User.objects.get(email=email)
except User.DoesNotExist:
    print("user not found")
    sys.exit(1)

groups = set(user.groups.values_list("name", flat=True))
errors = []
if user.is_staff != expected_staff:
    errors.append("is_staff mismatch")
if user.is_superuser != expected_superuser:
    errors.append("is_superuser mismatch")
missing = sorted(expected_groups - groups)
if missing:
    errors.append("missing groups: " + ", ".join(missing))
unexpected_owned = sorted((groups & {
    "Invoice managers",
    "News administrators",
    "Membership administrators",
    "Election administrators",
    "Accounting managers",
}) - expected_groups)
if unexpected_owned:
    errors.append("unexpected Keycloak-owned groups: " + ", ".join(unexpected_owned))

if errors:
    print("; ".join(errors))
    sys.exit(1)

print("role sync state ok")
PY
  then
    vc_pass "${label} Django role state matches Keycloak"
  else
    vc_fail "${label} Django role state matches Keycloak ($(tr '\n' ';' < "$output_file" | sed -E 's/[[:space:]]+/ /g'))"
  fi
}

assert_route_allowed() {
  local label="$1"
  local cookie_file="$2"
  local path="$3"
  local marker="$4"
  local body_file="${tmp_dir}/${label//[^A-Za-z0-9_.-]/_}.allowed.body"
  local status
  local url

  url="$(vc_url_join "$PGEU_URL" "$path")"
  status="$(curl "${curl_args[@]}" --cookie "$cookie_file" --output "$body_file" --write-out '%{http_code}' "$url" || true)"
  if [[ "$status" == "200" ]]; then
    vc_pass "${label} can access ${path}"
  else
    vc_fail "${label} can access ${path}; status=${status:-000}"
    return
  fi

  if [[ -n "$marker" ]]; then
    if grep -Fqi "$marker" "$body_file"; then
      vc_pass "${label} ${path} contains marker: ${marker}"
    else
      vc_fail "${label} ${path} contains marker: ${marker}"
    fi
  fi
}

assert_route_denied() {
  local label="$1"
  local cookie_file="$2"
  local path="$3"
  local body_file="${tmp_dir}/${label//[^A-Za-z0-9_.-]/_}.denied.body"
  local status
  local url

  url="$(vc_url_join "$PGEU_URL" "$path")"
  status="$(curl "${curl_args[@]}" --cookie "$cookie_file" --output "$body_file" --write-out '%{http_code}' "$url" || true)"
  if [[ "$status" == "403" ]]; then
    vc_pass "${label} cannot access ${path} after role revocation"
  else
    vc_fail "${label} cannot access ${path} after role revocation; status=${status:-000}"
  fi
}

check_functional_role() {
  local label="$1"
  local username="$2"
  local email="$3"
  local password_file="$4"
  local roles_csv="$5"
  local expected_group="$6"
  local route_path="$7"
  local marker="$8"
  local cookie_file

  cookie_file="${tmp_dir}/${label//[^A-Za-z0-9_.-]/_}.cookies"

  vc_info "checking ${label} functional access"
  set_keycloak_user_roles "$username" "$roles_csv"
  browser_login "$username" "$password_file" "$label" "$cookie_file"
  assert_django_user "$email" false false "$expected_group" "$label"
  assert_route_allowed "$label" "$cookie_file" "$route_path" "$marker"

  if vc_bool_true "$CHECK_REVOCATION"; then
    vc_info "checking ${label} revocation"
    set_keycloak_user_roles "$username" pgeu-user
    browser_login "$username" "$password_file" "${label} after revocation" "$cookie_file"
    assert_django_user "$email" false false "" "${label} after revocation"
    assert_route_denied "${label} after revocation" "$cookie_file" "$route_path"

    set_keycloak_user_roles "$username" "$roles_csv"
    browser_login "$username" "$password_file" "${label} after restore" "$cookie_file"
    assert_django_user "$email" false false "$expected_group" "${label} after restore"
    assert_route_allowed "${label} after restore" "$cookie_file" "$route_path" "$marker"
  fi
}

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

vc_info "Keycloak/PGEU role-sync smoke test"
vc_info "checking required commands"
for cmd in curl python3 docker; do
  vc_require_cmd "$cmd"
done

vc_info "checking deployed Keycloak role and mapper model"
if scripts/sync-keycloak-role-model.sh --env-file "$ENV_FILE" check; then
  vc_pass "deployed Keycloak role and mapper model matches the template"
else
  vc_fail "deployed Keycloak role and mapper model matches the template"
fi

scoped_groups_manifest="$(env_default KEYCLOAK_SCOPED_GROUPS_MANIFEST "")"
if [[ -n "$scoped_groups_manifest" ]]; then
  scoped_group_args=(--env-file "$ENV_FILE" --manifest "$scoped_groups_manifest")
  case "$(env_default KEYCLOAK_SCOPED_GROUPS_REQUIRE_EMPTY_MEMBERSHIPS false)" in
    1|true|TRUE|yes|YES|on|ON)
      scoped_group_args+=(--require-empty-memberships)
      ;;
  esac
  if scripts/sync-keycloak-scoped-groups.sh "${scoped_group_args[@]}" check; then
    vc_pass "deployed Keycloak scoped groups match the inventory manifest"
  else
    vc_fail "deployed Keycloak scoped groups match the inventory manifest"
  fi
else
  vc_pass "scoped-group check skipped until an inventory manifest is configured"
fi

vc_require_file "$normal_password_file" "normal validation password file exists"
for role_case in "${role_cases[@]}"; do
  IFS='|' read -r label _username _email password_file _roles_csv _expected_group _route_path _marker <<< "$role_case"
  vc_require_file "$password_file" "${label} validation password file exists"
done
vc_require_file "$superadmin_password_file" "superadmin validation password file exists"

vc_info "normalizing validation Keycloak roles"
set_keycloak_user_roles "$normal_user" pgeu-user
for role_case in "${role_cases[@]}"; do
  IFS='|' read -r _label username _email _password_file roles_csv _expected_group _route_path _marker <<< "$role_case"
  set_keycloak_user_roles "$username" "$roles_csv"
done
set_keycloak_user_roles "$superadmin_user" pgeu-superadmin
vc_pass "validation Keycloak role assignments normalized"

vc_info "checking normal user role sync"
browser_login "$normal_user" "$normal_password_file" "normal user"
assert_django_user "$normal_email" false false "" "normal user"

vc_info "checking mapped manager role functional access and revocation"
for role_case in "${role_cases[@]}"; do
  IFS='|' read -r label username email password_file roles_csv expected_group route_path marker <<< "$role_case"
  check_functional_role "$label" "$username" "$email" "$password_file" "$roles_csv" "$expected_group" "$route_path" "$marker"
done

vc_info "checking superadmin role sync"
browser_login "$superadmin_user" "$superadmin_password_file" "superadmin user"
assert_django_user "$superadmin_email" true true "" "superadmin user"

if [[ $VALIDATION_FAILURES -eq 0 ]]; then
  vc_pass "Keycloak/PGEU role-sync smoke test passed"
else
  printf '[XX] Keycloak/PGEU role-sync smoke test failed with %s issue(s)\n' "$VALIDATION_FAILURES" >&2
  exit 1
fi
