#!/usr/bin/env bash
set +x
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/validation-common.sh
. "${SCRIPT_DIR}/validation-common.sh"

cd "$REPO_ROOT"

ENV_FILE="${PGEU_STACK_ENV_FILE:-.env}"
COMPOSE_FILE="${PGEU_COMPOSE_FILE:-compose.yaml}"
PGEU_URL=""
KEYCLOAK_REALM_URL=""
CA_ROOT=""
TARGET_IP=""
TLS_VERIFY="${PGEU_SCOPED_SMOKE_TLS_VERIFY:-true}"
CONNECT_TIMEOUT="${PGEU_SCOPED_SMOKE_CONNECT_TIMEOUT:-5}"
MAX_TIME="${PGEU_SCOPED_SMOKE_MAX_TIME:-30}"

usage() {
  cat <<'USAGE'
Usage: scripts/smoke-keycloak-scoped-authorization.sh [options]

Runs a destructive, disposable scoped-authorization test against staging only.
It creates temporary PGEU fixtures and Keycloak groups, exercises a real OIDC
login/grant/revoke cycle, then removes every test-owned artifact.

Required safety controls:
  PGEU_SCOPED_SMOKE_CONFIRM=disposable-staging
  --target-ip PRIVATE_IP  Explicit loopback or RFC1918 target; public DNS is
                          never used. Use 127.0.0.1 on the staging host.

Options:
  --env-file PATH       Runtime env file. Default: .env
  --compose-file PATH   Compose file. Default: compose.yaml
  --pgeu-url URL        PGEU public base URL.
  --keycloak-url URL    Keycloak realm base URL.
  --ca-root PATH        CA root for TLS verification.
  --target-ip IP        Required explicit IPv4 loopback/RFC1918 target.
  --insecure            Disable TLS verification for this staging run.

The script never prints credentials, email addresses, cookies, OAuth values,
tokens, raw claims, or database rows. It hard-refuses auth.foss-north.se even
when that hostname is resolved to a private target.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --compose-file)
      COMPOSE_FILE="$2"
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
    --target-ip)
      TARGET_IP="$2"
      shift 2
      ;;
    --insecure)
      TLS_VERIFY=false
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

if [[ "${PGEU_SCOPED_SMOKE_CONFIRM:-}" != "disposable-staging" ]]; then
  vc_die "set PGEU_SCOPED_SMOKE_CONFIRM=disposable-staging for this destructive staging-only test"
fi
if [[ -z "$TARGET_IP" ]]; then
  vc_die "--target-ip is required; use 127.0.0.1 on the staging host"
fi
if ! python3 - "$TARGET_IP" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)

private_v4 = (
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
)
if address.version != 4:
    raise SystemExit(1)
if not (address.is_loopback or any(address in network for network in private_v4)):
    raise SystemExit(1)
PY
then
  vc_die "--target-ip must be an explicit IPv4 loopback or RFC1918 staging address"
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

normalize_url() {
  printf '%s' "${1%/}"
}

keycloak_host="$(env_default KEYCLOAK_HOST keycloak.localhost)"
keycloak_realm="$(env_default KEYCLOAK_REALM pgeu)"
pgeu_host="$(env_default PGEU_HOST pgeu.localhost)"

PGEU_URL="$(normalize_url "${PGEU_URL:-${PGEU_SCOPED_SMOKE_PGEU_URL:-$(env_default PGEU_SITE_BASE "https://${pgeu_host}")}}")"
KEYCLOAK_REALM_URL="$(normalize_url "${KEYCLOAK_REALM_URL:-${PGEU_SCOPED_SMOKE_KEYCLOAK_REALM_URL:-$(env_default PGEU_KEYCLOAK_BASE_URL "https://${keycloak_host}/realms/${keycloak_realm}")}}")"
CA_ROOT="${CA_ROOT:-${PGEU_SCOPED_SMOKE_CA_ROOT:-$(env_default STEPCA_ROOT_CERT runtime/certs/stepca/root_ca.crt)}}"
CLIENT_ID="$(env_default PGEU_KEYCLOAK_CLIENT_ID pgeu)"
VALIDATION_USER="$(env_default KEYCLOAK_VALIDATION_USER pgeu-test)"
VALIDATION_EMAIL="$(env_default KEYCLOAK_VALIDATION_EMAIL "${VALIDATION_USER}@${pgeu_host}")"
VALIDATION_PASSWORD_FILE="$(env_default KEYCLOAK_VALIDATION_PASSWORD_FILE runtime/secrets/keycloak-pgeu-test-password)"
PGEU_LOGIN_URL="$(vc_url_join "$PGEU_URL" /accounts/login/keycloak/)"
PGEU_PUBLIC_HOST="$(vc_url_host "$PGEU_URL")"
KEYCLOAK_PUBLIC_HOST="$(vc_url_host "$KEYCLOAK_REALM_URL")"

if [[ "$keycloak_realm" != "pgeu" || "$CLIENT_ID" != "pgeu" ]]; then
  vc_die "this smoke test is restricted to the pgeu realm and pgeu client"
fi
for candidate_url in "$KEYCLOAK_REALM_URL" "$PGEU_URL"; do
  if [[ "$(vc_url_host "$candidate_url")" == "auth.foss-north.se" ]]; then
    vc_die "refusing to run scoped authorization smoke against the production auth host"
  fi
done
if [[ "$KEYCLOAK_REALM_URL" == "https://auth.foss-north.se/realms/pgeu" ]]; then
  vc_die "refusing to run scoped authorization smoke against the production issuer"
fi

for cmd in curl docker jq python3; do
  command -v "$cmd" >/dev/null 2>&1 || vc_die "missing required command: $cmd"
done
[[ -f "$ENV_FILE" ]] || vc_die "runtime env file not found"
[[ -f "$COMPOSE_FILE" ]] || vc_die "Compose file not found"
[[ -s "$VALIDATION_PASSWORD_FILE" ]] || vc_die "normal validation password file is missing or empty"

compose_cmd=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
curl_args=(
  --silent
  --show-error
  --noproxy '*'
  --connect-timeout "$CONNECT_TIMEOUT"
  --max-time "$MAX_TIME"
)
if vc_bool_true "$TLS_VERIFY"; then
  [[ -f "$CA_ROOT" ]] || vc_die "CA root certificate file is required for TLS verification"
  curl_args+=(--cacert "$CA_ROOT")
else
  curl_args+=(--insecure)
  vc_info "TLS verification disabled for this staging-only smoke run"
fi
for public_url in "$PGEU_URL" "$KEYCLOAK_REALM_URL"; do
  public_host="$(vc_url_host "$public_url")"
  [[ -n "$public_host" ]] || vc_die "configured public URL has no hostname"
  curl_args+=(--resolve "${public_host}:80:${TARGET_IP}")
  curl_args+=(--resolve "${public_host}:443:${TARGET_IP}")
done

tmp_dir="$(mktemp -d)"
chmod 0700 "$tmp_dir"
manifest_file="${tmp_dir}/scoped-groups.json"
state_file="${tmp_dir}/fixture-state.json"
direct_roles_file="${tmp_dir}/direct-roles.json"
effective_roles_file="${tmp_dir}/effective-roles.json"
created_parents_file="${tmp_dir}/created-parent-paths"
owned_roots_file="${tmp_dir}/owned-resource-roots"
scanner_id_file="${tmp_dir}/scanner-id"
cookie_file="${tmp_dir}/browser.cookies"
run_slug="kcsmk$(date -u +%s)${RANDOM}"
run_slug="${run_slug:0:28}"
keycloak_ready=false
fixtures_started=false
roles_snapshotted=false
cleanup_started=false
validation_user_id=""
client_uuid=""

kcadm() {
  "${compose_cmd[@]}" exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@" </dev/null
}

keycloak_login() {
  # shellcheck disable=SC2016
  "${compose_cmd[@]}" exec -T keycloak bash -lc '
set -euo pipefail
admin_password="$(tr -d "\r\n" < /run/secrets/keycloak_admin_password)"
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://127.0.0.1:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN" \
  --password "$admin_password" >/dev/null
' </dev/null
}

find_group_id_by_path() {
  local path="$1"
  local response_file="${tmp_dir}/group-by-path.json"
  local error_file="${tmp_dir}/group-by-path.err"
  local group_id=""

  # Keycloak's paginated child representations can lag immediately after a
  # hierarchy write. The dedicated path endpoint resolves the canonical group
  # atomically and also avoids repeatedly walking every ancestor.
  if ! kcadm get "group-by-path/${path#/}" \
      -r "$keycloak_realm" \
      --fields id,path >"$response_file" 2>"$error_file"; then
    if grep -Eqi '404|not[[:space:]-]+found' "$error_file"; then
      return 1
    fi
    return 2
  fi
  group_id="$(
    jq -er --arg path "$path" \
      'select(type == "object" and .path == $path) | .id | select(type == "string" and length > 0)' \
      "$response_file" 2>/dev/null || true
  )"
  [[ -n "$group_id" ]] || return 2
  printf '%s' "$group_id"
}

add_group_membership() {
  local group_id="$1"
  kcadm update "users/${validation_user_id}/groups/${group_id}" \
    -r "$keycloak_realm" \
    -s "realm=${keycloak_realm}" \
    -s "userId=${validation_user_id}" \
    -s "groupId=${group_id}" \
    -n >/dev/null 2>&1
}

remove_group_membership() {
  local group_id="$1"
  kcadm delete "users/${validation_user_id}/groups/${group_id}" \
    -r "$keycloak_realm" >/dev/null 2>&1 || true
}

remove_all_test_memberships() {
  local path group_id lookup_status
  local failed=false
  [[ "$keycloak_ready" == true && -s "$manifest_file" && -n "$validation_user_id" ]] || return 0
  while IFS= read -r path; do
    if group_id="$(find_group_id_by_path "$path")"; then
      remove_group_membership "$group_id" || failed=true
    else
      lookup_status=$?
      [[ $lookup_status -eq 1 ]] || failed=true
    fi
  done < <(jq -r '.groups[].path' "$manifest_file")
  [[ "$failed" == false ]]
}

restore_direct_roles() {
  local role_name
  local current_file="${tmp_dir}/cleanup-current-direct.json"
  local current_names_file="${tmp_dir}/cleanup-current-direct-names.json"
  [[ "$keycloak_ready" == true && "$roles_snapshotted" == true ]] || return 0

  if ! kcadm get "users/${validation_user_id}/role-mappings/clients/${client_uuid}" \
      -r "$keycloak_realm" >"$current_file" 2>/dev/null; then
    return 1
  fi
  jq -c '[.[].name] | sort' "$current_file" > "$current_names_file" || return 1
  if [[ "$(<"$current_names_file")" == "$(<"$direct_roles_file")" ]]; then
    return 0
  fi
  while IFS= read -r role_name; do
    [[ -n "$role_name" ]] || continue
    kcadm remove-roles -r "$keycloak_realm" \
      --uusername "$VALIDATION_USER" \
      --cclientid "$CLIENT_ID" \
      --rolename "$role_name" >/dev/null 2>&1 || return 1
  done < <(jq -r '.[].name' "$current_file")
  while IFS= read -r role_name; do
    [[ -n "$role_name" ]] || continue
    kcadm add-roles -r "$keycloak_realm" \
      --uusername "$VALIDATION_USER" \
      --cclientid "$CLIENT_ID" \
      --rolename "$role_name" >/dev/null 2>&1 || return 1
  done < <(jq -r '.[]' "$direct_roles_file")
}

delete_group_if_empty() {
  local group_id="$1"
  local children_file="${tmp_dir}/cleanup-group-children.json"
  local members_file="${tmp_dir}/cleanup-group-members.json"
  local roles_file="${tmp_dir}/cleanup-group-roles.json"

  kcadm get "groups/${group_id}/children" -r "$keycloak_realm" -q first=0 -q max=2 >"$children_file" 2>/dev/null || return 1
  kcadm get "groups/${group_id}/members" -r "$keycloak_realm" -q first=0 -q max=2 >"$members_file" 2>/dev/null || return 1
  kcadm get "groups/${group_id}/role-mappings" -r "$keycloak_realm" >"$roles_file" 2>/dev/null || return 1
  jq -e 'length == 0' "$children_file" >/dev/null || return 1
  jq -e 'length == 0' "$members_file" >/dev/null || return 1
  jq -e '((.realmMappings // []) | length) == 0 and ((.clientMappings // {}) | length) == 0' "$roles_file" >/dev/null || return 1
  kcadm delete "groups/${group_id}" -r "$keycloak_realm" >/dev/null 2>&1
}

delete_owned_group_tree() {
  local path group_id index lookup_status
  local -a parent_paths
  local failed=false

  [[ "$keycloak_ready" == true ]] || return 0
  if [[ -s "$owned_roots_file" ]]; then
    while IFS= read -r path; do
      if group_id="$(find_group_id_by_path "$path")"; then
        kcadm delete "groups/${group_id}" -r "$keycloak_realm" >/dev/null 2>&1 || failed=true
      else
        lookup_status=$?
        [[ $lookup_status -eq 1 ]] || failed=true
      fi
    done < "$owned_roots_file"
  fi
  # Never prune shared parents when an owned resource root could not be
  # inspected or removed. Doing so could detach a still-live subtree.
  [[ "$failed" == false ]] || return 1
  if [[ -s "$created_parents_file" ]]; then
    mapfile -t parent_paths < "$created_parents_file"
    for ((index=${#parent_paths[@]} - 1; index >= 0; index--)); do
      path="${parent_paths[$index]}"
      if group_id="$(find_group_id_by_path "$path")"; then
        delete_group_if_empty "$group_id" || return 1
      else
        lookup_status=$?
        [[ $lookup_status -eq 1 ]] || return 1
      fi
    done
  fi
  [[ "$failed" == false ]]
}

django_action() {
  local action="$1"
  local output_file="${tmp_dir}/django-${action}.out"
  local error_file="${tmp_dir}/django-${action}.err"
  local binding_preexisting=unknown
  local country_created=false
  local scanner_id=""

  if [[ -s "$state_file" ]]; then
    binding_preexisting="$(jq -r '.binding_preexisting' "$state_file")"
    country_created="$(jq -r '.country_created' "$state_file")"
  fi
  if [[ -s "$scanner_id_file" ]]; then
    scanner_id="$(tr -d '\r\n' < "$scanner_id_file")"
  fi

  if ! "${compose_cmd[@]}" exec -T \
      -e "SMOKE_ACTION=${action}" \
      -e "SMOKE_RUN_SLUG=${run_slug}" \
      -e "SMOKE_VALIDATION_EMAIL=${VALIDATION_EMAIL}" \
      -e "SMOKE_ISSUER=${KEYCLOAK_REALM_URL}" \
      -e "SMOKE_BINDING_PREEXISTING=${binding_preexisting}" \
      -e "SMOKE_COUNTRY_CREATED=${country_created}" \
      -e "SMOKE_SCANNER_ID=${scanner_id}" \
      pgeu-web python manage.py shell >"$output_file" 2>"$error_file" <<'PY'
import json
import os
import sys
from datetime import timedelta

from django.contrib.auth.models import User
from django.db import transaction
from django.utils import timezone

from postgresqleu.confreg.models import Conference, ConferenceRegistration, ConferenceSeries
from postgresqleu.confsponsor.benefitclasses import get_benefit_id
from postgresqleu.confsponsor.models import (
    ScannedAttendee,
    Sponsor,
    SponsorClaimedBenefit,
    SponsorScanner,
    SponsorshipBenefit,
    SponsorshipLevel,
)
from postgresqleu.confwiki.models import Wikipage
from postgresqleu.countries.models import Country
from postgresqleu.membership.models import Meeting, Member
from postgresqleu.util.models import KeycloakIdentityBinding, KeycloakRoleGrant
from postgresqleu.util.random import generate_random_token


action = os.environ["SMOKE_ACTION"]
run_slug = os.environ["SMOKE_RUN_SLUG"]
email = os.environ["SMOKE_VALIDATION_EMAIL"]
issuer = os.environ["SMOKE_ISSUER"].rstrip("/")


def require(condition, label):
    if not condition:
        raise AssertionError(label)


def validation_user():
    users = list(User.objects.filter(email__iexact=email)[:2])
    require(len(users) == 1, "validation user must be unambiguous")
    require(users[0].is_active, "validation user must be active")
    return users[0]


def fixture_objects():
    return {
        "primary_series": ConferenceSeries.objects.get(name=f"Scoped smoke primary {run_slug}"),
        "collision_series": ConferenceSeries.objects.get(name=f"Scoped smoke collision {run_slug}"),
        "primary_conference": Conference.objects.get(urlname=run_slug),
        "sibling_conference": Conference.objects.get(urlname=f"{run_slug}s"),
        "primary_registration": ConferenceRegistration.objects.get(
            conference__urlname=run_slug,
            firstname="Scoped",
            lastname="Validation",
        ),
        "sibling_registration": ConferenceRegistration.objects.get(
            conference__urlname=f"{run_slug}s",
            firstname="Scoped",
            lastname="Sibling",
        ),
        "scan_target_registration": ConferenceRegistration.objects.get(
            conference__urlname=run_slug,
            firstname="Scoped",
            lastname="ScanTarget",
        ),
        "sponsor": Sponsor.objects.get(name=f"Scoped smoke sponsor {run_slug}"),
        "sibling_sponsor": Sponsor.objects.get(name=f"Scoped smoke sibling sponsor {run_slug}"),
        "meeting": Meeting.objects.get(name=f"Scoped smoke meeting {run_slug}"),
        "sibling_meeting": Meeting.objects.get(name=f"Scoped smoke sibling meeting {run_slug}"),
        "wiki": Wikipage.objects.get(conference__urlname=run_slug, url="scoped-smoke"),
        "sibling_wiki": Wikipage.objects.get(conference__urlname=f"{run_slug}s", url="scoped-smoke"),
    }


def expected_claims(objects):
    conference_slug = objects["primary_conference"].urlname
    return {
        f"/pgeu/series/{objects['primary_series'].pk}/roles/admin": "pgeu-series-admin",
        f"/pgeu/series/{objects['collision_series'].pk}/roles/admin": "pgeu-series-admin",
        f"/pgeu/conferences/{conference_slug}/roles/admin": "pgeu-conference-admin",
        f"/pgeu/conferences/{conference_slug}/roles/tester": "pgeu-conference-tester",
        f"/pgeu/conferences/{conference_slug}/roles/talkvoter": "pgeu-conference-talkvoter",
        f"/pgeu/conferences/{conference_slug}/roles/staff": "pgeu-conference-staff",
        f"/pgeu/conferences/{conference_slug}/roles/volunteer": "pgeu-conference-volunteer",
        f"/pgeu/conferences/{conference_slug}/roles/checkin-processor": "pgeu-conference-checkin-processor",
        f"/pgeu/conferences/{conference_slug}/wiki/{objects['wiki'].url}/roles/viewer": "pgeu-wiki-viewer",
        f"/pgeu/conferences/{conference_slug}/wiki/{objects['wiki'].url}/roles/editor": "pgeu-wiki-editor",
        f"/pgeu/sponsors/{objects['sponsor'].pk}/roles/manager": "pgeu-sponsor-manager",
        f"/pgeu/sponsors/{objects['sponsor'].pk}/roles/badge-scanner": "pgeu-sponsor-badge-scanner",
        f"/pgeu/meetings/{objects['meeting'].pk}/roles/admin": "pgeu-meeting-admin",
    }


def assert_sibling_negative(user, objects):
    sibling_conference = objects["sibling_conference"]
    sibling_registration = objects["sibling_registration"]
    for relation in ("administrators", "testers", "talkvoters", "staff"):
        require(not getattr(sibling_conference, relation).filter(pk=user.pk).exists(), f"sibling {relation} must remain absent")
    for relation in ("volunteers", "checkinprocessors"):
        require(not getattr(sibling_conference, relation).filter(pk=sibling_registration.pk).exists(), f"sibling {relation} must remain absent")
    require(not objects["sibling_wiki"].viewer_attendee.filter(pk=sibling_registration.pk).exists(), "sibling wiki viewer must remain absent")
    require(not objects["sibling_wiki"].editor_attendee.filter(pk=sibling_registration.pk).exists(), "sibling wiki editor must remain absent")
    require(not objects["sibling_sponsor"].managers.filter(pk=user.pk).exists(), "sibling sponsor manager must remain absent")
    require(not SponsorScanner.objects.filter(sponsor=objects["sibling_sponsor"]).exists(), "sibling scanner must remain absent")
    require(not objects["sibling_meeting"].meetingadmins.filter(user=user).exists(), "sibling meeting admin must remain absent")


def assert_owned_relations_absent(user, objects, scanner_id):
    primary_series = objects["primary_series"]
    collision_series = objects["collision_series"]
    conference = objects["primary_conference"]
    registration = objects["primary_registration"]
    require(not primary_series.administrators.filter(pk=user.pk).exists(), "owned series relation must be revoked")
    require(collision_series.administrators.filter(pk=user.pk).exists(), "local series collision must be preserved")
    for relation in ("administrators", "testers", "talkvoters", "staff"):
        require(not getattr(conference, relation).filter(pk=user.pk).exists(), f"owned {relation} must be revoked")
    for relation in ("volunteers", "checkinprocessors"):
        require(not getattr(conference, relation).filter(pk=registration.pk).exists(), f"owned {relation} must be revoked")
    require(not objects["wiki"].viewer_attendee.filter(pk=registration.pk).exists(), "owned wiki viewer must be revoked")
    require(not objects["wiki"].editor_attendee.filter(pk=registration.pk).exists(), "owned wiki editor must be revoked")
    require(not objects["sponsor"].managers.filter(pk=user.pk).exists(), "owned sponsor manager must be revoked")
    require(not SponsorScanner.objects.filter(pk=scanner_id).exists(), "exact owned scanner row must be revoked")
    require(not SponsorScanner.objects.filter(sponsor=objects["sponsor"]).exists(), "scanner token authorization must be revoked")
    require(not objects["meeting"].meetingadmins.filter(user=user).exists(), "owned meeting admin must be revoked")


if action == "create":
    with transaction.atomic():
        user = validation_user()
        require(not user.is_staff and not user.is_superuser, "validation user must be nonprivileged")
        manager_groups = {
            "Invoice managers",
            "News administrators",
            "Membership administrators",
            "Election administrators",
            "Accounting managers",
        }
        require(not user.groups.filter(name__in=manager_groups).exists(), "validation user must have no global manager group")
        require(not Conference.objects.filter(urlname__in=(run_slug, f"{run_slug}s")).exists(), "run slug must be unused")
        require(not ConferenceSeries.objects.filter(name__contains=run_slug).exists(), "run series must be unused")
        require(not Meeting.objects.filter(name__contains=run_slug).exists(), "run meetings must be unused")
        require(not Member.objects.filter(user=user).exists(), "validation user must not already be a member fixture")
        for field in ("relation_target", "relation_record"):
            KeycloakRoleGrant._meta.get_field(field)

        binding = KeycloakIdentityBinding.objects.filter(issuer=issuer, user=user).first()
        binding_preexisting = binding is not None
        if binding is not None:
            require(not binding.role_grants.exists(), "validation binding must begin with no scoped grants")

        country, country_created = Country.objects.get_or_create(
            iso="ZZ",
            defaults={"name": "SCOPED SMOKE", "printable_name": "Scoped smoke", "iso3": "ZZZ", "numcode": 999},
        )
        primary_series = ConferenceSeries.objects.create(name=f"Scoped smoke primary {run_slug}")
        collision_series = ConferenceSeries.objects.create(name=f"Scoped smoke collision {run_slug}")
        collision_series.administrators.add(user)

        today = timezone.localdate()
        common_conference = {
            "startdate": today + timedelta(days=30),
            "enddate": today + timedelta(days=31),
            "location": "Disposable staging",
            "contactaddr": f"contact-{run_slug}@invalid.example",
            "sponsoraddr": f"sponsor-{run_slug}@invalid.example",
            "notifyaddr": f"notify-{run_slug}@invalid.example",
            "confurl": f"https://{run_slug}.invalid.example/",
            "askbadgescan": True,
        }
        primary_conference = Conference.objects.create(
            urlname=run_slug,
            conferencename=f"Scoped smoke primary {run_slug}",
            series=primary_series,
            **common_conference,
        )
        sibling_values = dict(common_conference)
        sibling_values.update({
            "contactaddr": f"contact-{run_slug}s@invalid.example",
            "sponsoraddr": f"sponsor-{run_slug}s@invalid.example",
            "notifyaddr": f"notify-{run_slug}s@invalid.example",
            "confurl": f"https://{run_slug}s.invalid.example/",
        })
        sibling_conference = Conference.objects.create(
            urlname=f"{run_slug}s",
            conferencename=f"Scoped smoke sibling {run_slug}",
            series=collision_series,
            **sibling_values,
        )

        now = timezone.now()

        def registration(conference, attendee, first, last, address):
            tokens = [generate_random_token() for _ in range(3)]
            require(all(len(token) == 64 for token in tokens), "registration tokens must be 64 characters")
            return ConferenceRegistration.objects.create(
                conference=conference,
                attendee=attendee,
                registrator=user,
                firstname=first,
                lastname=last,
                email=address,
                country=country,
                created=now,
                payconfirmedat=now,
                payconfirmedby="scoped-smoke",
                regtoken=tokens[0],
                idtoken=tokens[1],
                publictoken=tokens[2],
            )

        primary_registration = registration(
            primary_conference,
            user,
            "Scoped",
            "Validation",
            f"validation-{run_slug}@invalid.example",
        )
        sibling_registration = registration(
            sibling_conference,
            user,
            "Scoped",
            "Sibling",
            f"sibling-{run_slug}@invalid.example",
        )
        scan_user = User.objects.create_user(
            username=f"scan-{run_slug}@invalid.example",
            email=f"scan-{run_slug}@invalid.example",
        )
        scan_user.set_unusable_password()
        scan_user.save(update_fields=["password"])
        scan_target_registration = registration(
            primary_conference,
            scan_user,
            "Scoped",
            "ScanTarget",
            f"scan-{run_slug}@invalid.example",
        )

        member = Member.objects.create(
            user=user,
            fullname="Scoped Validation",
            country=country,
            paiduntil=today + timedelta(days=365),
            membersince=today,
        )
        meeting = Meeting.objects.create(
            name=f"Scoped smoke meeting {run_slug}",
            dateandtime=now + timedelta(days=10),
            allmembers=True,
        )
        sibling_meeting = Meeting.objects.create(
            name=f"Scoped smoke sibling meeting {run_slug}",
            dateandtime=now + timedelta(days=11),
            allmembers=True,
        )

        level = SponsorshipLevel.objects.create(
            conference=primary_conference,
            levelname=f"Scoped smoke level {run_slug}",
            urlname="scoped-smoke",
            levelcost=1,
            paymentdueby=today + timedelta(days=90),
        )
        sibling_level = SponsorshipLevel.objects.create(
            conference=sibling_conference,
            levelname=f"Scoped smoke sibling level {run_slug}",
            urlname="scoped-smoke",
            levelcost=1,
            paymentdueby=today + timedelta(days=90),
        )
        sponsor = Sponsor.objects.create(
            conference=primary_conference,
            name=f"Scoped smoke sponsor {run_slug}",
            displayname=f"Scoped smoke sponsor {run_slug}",
            level=level,
            confirmed=True,
            confirmedat=now,
            confirmedby="scoped-smoke",
            signupat=now,
        )
        sibling_sponsor = Sponsor.objects.create(
            conference=sibling_conference,
            name=f"Scoped smoke sibling sponsor {run_slug}",
            displayname=f"Scoped smoke sibling sponsor {run_slug}",
            level=sibling_level,
            confirmed=True,
            confirmedat=now,
            confirmedby="scoped-smoke",
            signupat=now,
        )
        benefit = SponsorshipBenefit.objects.create(
            level=level,
            benefitname="Disposable badge scanning",
            benefit_class=get_benefit_id("badgescanning.BadgeScanning"),
            class_parameters={},
        )
        SponsorClaimedBenefit.objects.create(
            sponsor=sponsor,
            benefit=benefit,
            claimedat=now,
            claimedby=user,
            declined=False,
            confirmed=True,
            claimjson={},
        )

        wiki = Wikipage.objects.create(
            conference=primary_conference,
            url="scoped-smoke",
            title="Scoped smoke",
            author=primary_registration,
            contents="Disposable scoped authorization fixture",
        )
        sibling_wiki = Wikipage.objects.create(
            conference=sibling_conference,
            url="scoped-smoke",
            title="Scoped smoke sibling",
            author=sibling_registration,
            contents="Disposable sibling fixture",
        )

        state = {
            "binding_preexisting": binding_preexisting,
            "country_created": country_created,
            "primary_series_id": primary_series.pk,
            "collision_series_id": collision_series.pk,
            "primary_conference": primary_conference.urlname,
            "sibling_conference": sibling_conference.urlname,
            "primary_registration_id": primary_registration.pk,
            "sibling_registration_id": sibling_registration.pk,
            "scan_target_registration_id": scan_target_registration.pk,
            "scan_user_id": scan_user.pk,
            "sponsor_id": sponsor.pk,
            "sibling_sponsor_id": sibling_sponsor.pk,
            "meeting_id": meeting.pk,
            "sibling_meeting_id": sibling_meeting.pk,
            "wiki_id": wiki.pk,
            "sibling_wiki_id": sibling_wiki.pk,
        }
        print("PGEU_SCOPED_STATE=" + json.dumps(state, sort_keys=True, separators=(",", ":")))

elif action == "assert_positive":
    user = validation_user()
    objects = fixture_objects()
    binding = KeycloakIdentityBinding.objects.get(issuer=issuer, user=user)
    claims = expected_claims(objects)
    grants = list(binding.role_grants.order_by("group_path"))
    require(len(grants) == 13, "exactly thirteen scoped grants must be recorded")
    require({grant.group_path: grant.client_role for grant in grants} == claims, "scoped claim ledger must match manifest")
    collision_path = f"/pgeu/series/{objects['collision_series'].pk}/roles/admin"
    require(sum(1 for grant in grants if grant.owned) == 12, "twelve grants must be Keycloak-owned")
    require(sum(1 for grant in grants if not grant.owned) == 1, "one local collision must be unowned")
    require(next(grant for grant in grants if grant.group_path == collision_path).owned is False, "series collision must be unowned")
    require(all(bool(grant.relation_target) for grant in grants), "all exact relation targets must be recorded")

    conference = objects["primary_conference"]
    registration = objects["primary_registration"]
    require(objects["primary_series"].administrators.filter(pk=user.pk).exists(), "owned series admin must be present")
    require(objects["collision_series"].administrators.filter(pk=user.pk).exists(), "local series collision must be present")
    for relation in ("administrators", "testers", "talkvoters", "staff"):
        require(getattr(conference, relation).filter(pk=user.pk).exists(), f"primary {relation} must be present")
    for relation in ("volunteers", "checkinprocessors"):
        require(getattr(conference, relation).filter(pk=registration.pk).exists(), f"primary {relation} must be present")
    require(objects["wiki"].viewer_attendee.filter(pk=registration.pk).exists(), "wiki viewer must be present")
    require(objects["wiki"].editor_attendee.filter(pk=registration.pk).exists(), "wiki editor must be present")
    require(objects["sponsor"].managers.filter(pk=user.pk).exists(), "sponsor manager must be present")
    require(objects["meeting"].meetingadmins.filter(user=user).exists(), "meeting admin must be present")
    scanner = SponsorScanner.objects.get(sponsor=objects["sponsor"], scanner=registration)
    require(len(scanner.token) == 64, "scanner token must be generated")
    scanner_grant = next(grant for grant in grants if grant.grant_type == "sponsor-badge-scanner")
    require(str(scanner_grant.relation_record) == str(scanner.pk), "scanner grant must record the exact scanner row")
    require(all(
        not grant.relation_record
        for grant in grants
        if grant.grant_type != "sponsor-badge-scanner"
    ), "non-scanner grants must not record a relation row")
    assert_sibling_negative(user, objects)
    print(f"PGEU_SCOPED_SCANNER_ID={scanner.pk}")

elif action == "detach":
    with transaction.atomic():
        objects = fixture_objects()
        registration = objects["primary_registration"]
        scanner = SponsorScanner.objects.get(pk=int(os.environ["SMOKE_SCANNER_ID"]))
        require(scanner.scanner_id == registration.pk, "scanner relation must target primary registration")
        ScannedAttendee.objects.create(
            sponsor=objects["sponsor"],
            scannedby=registration,
            attendee=objects["scan_target_registration"],
            firstscan=True,
            note="Disposable history-preservation proof",
        )
        registration.attendee = None
        registration.save(update_fields=["attendee"])
        require(ScannedAttendee.objects.filter(sponsor=objects["sponsor"], scannedby=registration).count() == 1, "scanner history must exist")
        print("PGEU_SCOPED_OK=detach")

elif action in ("assert_revoked", "assert_relinked"):
    user = validation_user()
    objects = fixture_objects()
    binding = KeycloakIdentityBinding.objects.get(issuer=issuer, user=user)
    scanner_id = int(os.environ["SMOKE_SCANNER_ID"])
    require(not binding.role_grants.exists(), "scoped ledger must be empty after revocation")
    assert_owned_relations_absent(user, objects, scanner_id)
    assert_sibling_negative(user, objects)
    require(
        ScannedAttendee.objects.filter(
            sponsor=objects["sponsor"],
            scannedby=objects["primary_registration"],
        ).count() == 1,
        "scanner history must be preserved",
    )
    expected_attendee = user.pk if action == "assert_relinked" else None
    require(objects["primary_registration"].attendee_id == expected_attendee, "registration link state mismatch")
    print(f"PGEU_SCOPED_OK={action}")

elif action == "relink":
    with transaction.atomic():
        user = validation_user()
        objects = fixture_objects()
        registration = objects["primary_registration"]
        require(registration.attendee_id is None, "registration must be detached before relink")
        registration.attendee = user
        registration.save(update_fields=["attendee"])
        binding = KeycloakIdentityBinding.objects.get(issuer=issuer, user=user)
        require(not binding.role_grants.exists(), "relink must not recreate ledger entries")
        assert_owned_relations_absent(user, objects, int(os.environ["SMOKE_SCANNER_ID"]))
        print("PGEU_SCOPED_OK=relink")

elif action == "cleanup":
    with transaction.atomic():
        users = list(User.objects.filter(email__iexact=email)[:2])
        user = users[0] if len(users) == 1 else None
        primary_series = ConferenceSeries.objects.filter(name=f"Scoped smoke primary {run_slug}").first()
        collision_series = ConferenceSeries.objects.filter(name=f"Scoped smoke collision {run_slug}").first()
        conferences = list(Conference.objects.filter(urlname__in=(run_slug, f"{run_slug}s")))
        registrations = list(ConferenceRegistration.objects.filter(conference__in=conferences))
        sponsors = list(Sponsor.objects.filter(conference__in=conferences))
        levels = list(SponsorshipLevel.objects.filter(conference__in=conferences))
        benefits = list(SponsorshipBenefit.objects.filter(level__in=levels))
        pages = list(Wikipage.objects.filter(conference__in=conferences))
        meetings = list(Meeting.objects.filter(
            name__in=(f"Scoped smoke meeting {run_slug}", f"Scoped smoke sibling meeting {run_slug}"),
        ))
        paths = []
        if primary_series is not None:
            paths.append(f"/pgeu/series/{primary_series.pk}/roles/admin")
        if collision_series is not None:
            paths.append(f"/pgeu/series/{collision_series.pk}/roles/admin")
        primary_conference = next((item for item in conferences if item.urlname == run_slug), None)
        if primary_conference is not None:
            paths.extend([
                f"/pgeu/conferences/{run_slug}/roles/admin",
                f"/pgeu/conferences/{run_slug}/roles/tester",
                f"/pgeu/conferences/{run_slug}/roles/talkvoter",
                f"/pgeu/conferences/{run_slug}/roles/staff",
                f"/pgeu/conferences/{run_slug}/roles/volunteer",
                f"/pgeu/conferences/{run_slug}/roles/checkin-processor",
            ])
            wiki = Wikipage.objects.filter(conference=primary_conference, url="scoped-smoke").first()
            if wiki is not None:
                paths.extend([
                    f"/pgeu/conferences/{run_slug}/wiki/scoped-smoke/roles/viewer",
                    f"/pgeu/conferences/{run_slug}/wiki/scoped-smoke/roles/editor",
                ])
            sponsor = Sponsor.objects.filter(conference=primary_conference, name=f"Scoped smoke sponsor {run_slug}").first()
            if sponsor is not None:
                paths.extend([
                    f"/pgeu/sponsors/{sponsor.pk}/roles/manager",
                    f"/pgeu/sponsors/{sponsor.pk}/roles/badge-scanner",
                ])
        meeting = Meeting.objects.filter(name=f"Scoped smoke meeting {run_slug}").first()
        if meeting is not None:
            paths.append(f"/pgeu/meetings/{meeting.pk}/roles/admin")

        if user is not None:
            binding = KeycloakIdentityBinding.objects.filter(issuer=issuer, user=user).first()
            if binding is not None:
                binding.role_grants.filter(group_path__in=paths).delete()
                if os.environ.get("SMOKE_BINDING_PREEXISTING") == "false" and not binding.role_grants.exists():
                    binding.delete()

        # Delete fixture dependencies explicitly before registrations and
        # conferences. Cascading directly from ConferenceSeries makes Django's
        # Collector defer fields on DiffableModel-based Wikipage rows; their
        # constructor then recursively refreshes those deferred fields.
        ScannedAttendee.objects.filter(sponsor__in=sponsors).delete()
        SponsorScanner.objects.filter(sponsor__in=sponsors).delete()
        for page in pages:
            page.delete()
        SponsorClaimedBenefit.objects.filter(sponsor__in=sponsors).delete()
        for benefit in benefits:
            benefit.delete()
        for sponsor in sponsors:
            sponsor.delete()
        for level in levels:
            level.delete()

        for conference in conferences:
            conference.administrators.clear()
            conference.testers.clear()
            conference.talkvoters.clear()
            conference.staff.clear()
            conference.volunteers.clear()
            conference.checkinprocessors.clear()
        for registration in registrations:
            registration.delete()
        for meeting in meetings:
            meeting.delete()
        if user is not None:
            Member.objects.filter(user=user).delete()
        for conference in conferences:
            conference.delete()
        for series in (primary_series, collision_series):
            if series is not None:
                series.delete()
        User.objects.filter(username=f"scan-{run_slug}@invalid.example").delete()
        if os.environ.get("SMOKE_COUNTRY_CREATED") == "true":
            country = Country.objects.filter(iso="ZZ", name="SCOPED SMOKE").first()
            if country is not None and not Member.objects.filter(country=country).exists() and not ConferenceRegistration.objects.filter(country=country).exists():
                country.delete()
        print("PGEU_SCOPED_OK=cleanup")
else:
    raise AssertionError("unknown scoped smoke action")
PY
  then
    return 1
  fi

  case "$action" in
    create)
      sed -n 's/^PGEU_SCOPED_STATE=//p' "$output_file" | tail -n 1
      ;;
    assert_positive)
      sed -n 's/^PGEU_SCOPED_SCANNER_ID=//p' "$output_file" | tail -n 1
      ;;
    *)
      grep -q "^PGEU_SCOPED_OK=${action}$" "$output_file"
      ;;
  esac
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
        if data.get("id", "") == "kc-form-login":
            self.actions.insert(0, action)
        else:
            self.actions.append(action)

parser = FormParser()
with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as handle:
    parser.feed(handle.read())
if not parser.actions:
    raise SystemExit(1)
print(urljoin(sys.argv[2], parser.actions[0]))
PY
}

join_redirect_url() {
  local base_url="$1"
  local location="$2"
  python3 - "$base_url" "$location" 2>/dev/null <<'PY'
import sys
from urllib.parse import urljoin

print(urljoin(sys.argv[1], sys.argv[2]))
PY
}

browser_url_is_allowed() {
  local url="$1"
  local host
  host="$(vc_url_host "$url" 2>/dev/null)" || return 1
  [[ "$host" == "$PGEU_PUBLIC_HOST" || "$host" == "$KEYCLOAK_PUBLIC_HOST" ]]
}

browser_login() {
  local label="$1"
  local headers_file="${tmp_dir}/browser.headers"
  local body_file="${tmp_dir}/browser.body"
  local curl_error_file="${tmp_dir}/browser.curl.err"
  local password_tmp="${tmp_dir}/browser.password"
  local status location action current_url
  local redirect_count

  tr -d '\r\n' < "$VALIDATION_PASSWORD_FILE" > "$password_tmp"
  chmod 0600 "$password_tmp"
  rm -f "$cookie_file"

  status="$(curl "${curl_args[@]}" --cookie-jar "$cookie_file" --dump-header "$headers_file" --output "$body_file" --write-out '%{http_code}' "$PGEU_LOGIN_URL" 2>"$curl_error_file" || true)"
  [[ "$status" =~ ^30[12378]$ ]] || return 1
  location="$(first_header "$headers_file" Location)"
  [[ -n "$location" ]] || return 1
  location="$(join_redirect_url "$PGEU_LOGIN_URL" "$location")" || return 1
  [[ "$(vc_url_host "$location" 2>/dev/null)" == "$KEYCLOAK_PUBLIC_HOST" ]] || return 1

  status="$(curl "${curl_args[@]}" --cookie "$cookie_file" --cookie-jar "$cookie_file" --dump-header "$headers_file" --output "$body_file" --write-out '%{http_code}' "$location" 2>"$curl_error_file" || true)"
  [[ "$status" == "200" ]] || return 1
  action="$(extract_login_action "$body_file" "$location" 2>/dev/null)" || return 1
  [[ "$(vc_url_host "$action" 2>/dev/null)" == "$KEYCLOAK_PUBLIC_HOST" ]] || return 1

  status="$(
    curl "${curl_args[@]}" \
      --cookie "$cookie_file" \
      --cookie-jar "$cookie_file" \
      --dump-header "$headers_file" \
      --output "$body_file" \
      --write-out '%{http_code}' \
      --data-urlencode "username=${VALIDATION_USER}" \
      --data-urlencode "password@${password_tmp}" \
      --data-urlencode "credentialId=" \
      "$action" 2>"$curl_error_file" || true
  )"
  current_url="$action"
  for redirect_count in {1..10}; do
    if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
      vc_pass "${label} completed through a fresh browser OIDC flow"
      return 0
    fi
    [[ "$status" =~ ^30[12378]$ ]] || return 1
    location="$(first_header "$headers_file" Location)"
    [[ -n "$location" ]] || return 1
    current_url="$(join_redirect_url "$current_url" "$location")" || return 1
    browser_url_is_allowed "$current_url" || return 1
    status="$(curl "${curl_args[@]}" --cookie "$cookie_file" --cookie-jar "$cookie_file" --dump-header "$headers_file" --output "$body_file" --write-out '%{http_code}' "$current_url" 2>"$curl_error_file" || true)"
  done
  return 1
}

cleanup() {
  local exit_status=$?
  local cleanup_failed=false
  [[ "$cleanup_started" == false ]] || return
  cleanup_started=true
  trap - EXIT
  set +e

  vc_info "removing disposable scoped-authorization artifacts"
  remove_all_test_memberships || cleanup_failed=true
  restore_direct_roles || cleanup_failed=true
  delete_owned_group_tree || cleanup_failed=true
  if [[ "$fixtures_started" == true ]]; then
    django_action cleanup >/dev/null || cleanup_failed=true
  fi
  rm -rf "$tmp_dir"

  if [[ "$cleanup_failed" == true ]]; then
    printf '[XX] scoped smoke cleanup did not fully converge; inspect staging before another run\n' >&2
    exit_status=1
  else
    vc_pass "disposable memberships, groups, fixtures, binding state, and direct roles restored"
  fi
  exit "$exit_status"
}
trap cleanup EXIT

vc_info "checking scoped smoke staging safety gates"
discovery_file="${tmp_dir}/discovery.json"
discovery_url="$(vc_url_join "$KEYCLOAK_REALM_URL" /.well-known/openid-configuration)"
if ! curl "${curl_args[@]}" --output "$discovery_file" --fail "$discovery_url"; then
  vc_die "Keycloak discovery failed through the explicit private target"
fi
discovered_issuer="$(jq -er '.issuer | select(type == "string")' "$discovery_file" 2>/dev/null || true)"
discovered_issuer="$(normalize_url "$discovered_issuer")"
if [[ -z "$discovered_issuer" || "$discovered_issuer" != "$KEYCLOAK_REALM_URL" ]]; then
  vc_die "Keycloak discovery issuer does not match the configured staging realm URL"
fi
if [[ "$(vc_url_host "$discovered_issuer")" == "auth.foss-north.se" ]]; then
  vc_die "discovery returned the production Keycloak issuer"
fi
vc_pass "explicit private target and non-production discovery issuer verified"

if ! scripts/sync-keycloak-role-model.sh --env-file "$ENV_FILE" --compose-file "$COMPOSE_FILE" check >/dev/null; then
  vc_die "deployed Keycloak scoped role and mapper model is not converged"
fi
vc_pass "deployed Keycloak role and mapper model is converged"

if ! keycloak_login >/dev/null 2>&1; then
  vc_die "could not authenticate the local Keycloak admin session"
fi
keycloak_ready=true

if ! kcadm get clients -r "$keycloak_realm" -q "clientId=${CLIENT_ID}" --fields id >"${tmp_dir}/clients.json" 2>/dev/null; then
  vc_die "could not inspect the staging Keycloak client"
fi
client_uuid="$(jq -er 'select(length == 1) | .[0].id' "${tmp_dir}/clients.json" 2>/dev/null || true)"
if ! kcadm get users -r "$keycloak_realm" -q "username=${VALIDATION_USER}" -q exact=true --fields id >"${tmp_dir}/users.json" 2>/dev/null; then
  vc_die "could not inspect the staging validation account"
fi
validation_user_id="$(jq -er 'select(length == 1) | .[0].id' "${tmp_dir}/users.json" 2>/dev/null || true)"
[[ -n "$client_uuid" && -n "$validation_user_id" ]] || vc_die "staging client or validation account is ambiguous"

if ! kcadm get "users/${validation_user_id}/role-mappings/clients/${client_uuid}" -r "$keycloak_realm" >"${tmp_dir}/direct-role-objects.json" 2>/dev/null; then
  vc_die "could not snapshot validation direct client roles"
fi
jq -c '[.[].name] | sort' "${tmp_dir}/direct-role-objects.json" > "$direct_roles_file"
roles_snapshotted=true
if ! kcadm get "users/${validation_user_id}/role-mappings/clients/${client_uuid}/composite" -r "$keycloak_realm" >"${tmp_dir}/effective-role-objects.json" 2>/dev/null; then
  vc_die "could not inspect validation effective client roles"
fi
jq -c '[.[].name | select(startswith("pgeu-"))] | sort' "${tmp_dir}/effective-role-objects.json" > "$effective_roles_file"
if [[ "$(<"$direct_roles_file")" != '["pgeu-user"]' || "$(<"$effective_roles_file")" != '["pgeu-user"]' ]]; then
  vc_die "validation account must begin with only the direct and effective pgeu-user role"
fi
vc_pass "validation account begins with the nonprivileged PGEU role only"

fixtures_started=true
fixture_state="$(django_action create || true)"
if [[ -z "$fixture_state" ]] || ! jq -e 'type == "object" and .binding_preexisting != null' >/dev/null 2>&1 <<< "$fixture_state"; then
  vc_die "could not create disposable PGEU authorization fixtures"
fi
printf '%s\n' "$fixture_state" > "$state_file"
vc_pass "disposable PGEU series, conference, registration, sponsor, member, meeting, and wiki fixtures created"

primary_series_id="$(jq -r '.primary_series_id' "$state_file")"
collision_series_id="$(jq -r '.collision_series_id' "$state_file")"
primary_conference="$(jq -r '.primary_conference' "$state_file")"
sponsor_id="$(jq -r '.sponsor_id' "$state_file")"
meeting_id="$(jq -r '.meeting_id' "$state_file")"

jq -n \
  --arg series_a "$primary_series_id" \
  --arg series_b "$collision_series_id" \
  --arg conference "$primary_conference" \
  --arg sponsor "$sponsor_id" \
  --arg meeting "$meeting_id" '
  {
    version: 1,
    groups: [
      {path: ("/pgeu/series/" + $series_a + "/roles/admin"), client_role: "pgeu-series-admin"},
      {path: ("/pgeu/series/" + $series_b + "/roles/admin"), client_role: "pgeu-series-admin"},
      {path: ("/pgeu/conferences/" + $conference + "/roles/admin"), client_role: "pgeu-conference-admin"},
      {path: ("/pgeu/conferences/" + $conference + "/roles/tester"), client_role: "pgeu-conference-tester"},
      {path: ("/pgeu/conferences/" + $conference + "/roles/talkvoter"), client_role: "pgeu-conference-talkvoter"},
      {path: ("/pgeu/conferences/" + $conference + "/roles/staff"), client_role: "pgeu-conference-staff"},
      {path: ("/pgeu/conferences/" + $conference + "/roles/volunteer"), client_role: "pgeu-conference-volunteer"},
      {path: ("/pgeu/conferences/" + $conference + "/roles/checkin-processor"), client_role: "pgeu-conference-checkin-processor"},
      {path: ("/pgeu/conferences/" + $conference + "/wiki/scoped-smoke/roles/viewer"), client_role: "pgeu-wiki-viewer"},
      {path: ("/pgeu/conferences/" + $conference + "/wiki/scoped-smoke/roles/editor"), client_role: "pgeu-wiki-editor"},
      {path: ("/pgeu/sponsors/" + $sponsor + "/roles/manager"), client_role: "pgeu-sponsor-manager"},
      {path: ("/pgeu/sponsors/" + $sponsor + "/roles/badge-scanner"), client_role: "pgeu-sponsor-badge-scanner"},
      {path: ("/pgeu/meetings/" + $meeting + "/roles/admin"), client_role: "pgeu-meeting-admin"}
    ]
  }' > "$manifest_file"

if ! scripts/sync-keycloak-scoped-groups.sh --env-file "$ENV_FILE" --compose-file "$COMPOSE_FILE" --manifest "$manifest_file" validate >/dev/null; then
  vc_die "generated disposable scoped group manifest is invalid"
fi

parent_paths=(/pgeu /pgeu/series /pgeu/conferences /pgeu/sponsors /pgeu/meetings)
for path in "${parent_paths[@]}"; do
  if find_group_id_by_path "$path" >/dev/null; then
    continue
  else
    lookup_status=$?
    [[ $lookup_status -eq 1 ]] || vc_die "could not safely inspect the existing Keycloak group hierarchy"
    printf '%s\n' "$path" >> "$created_parents_file"
  fi
done
resource_roots=(
  "/pgeu/series/${primary_series_id}"
  "/pgeu/series/${collision_series_id}"
  "/pgeu/conferences/${primary_conference}"
  "/pgeu/sponsors/${sponsor_id}"
  "/pgeu/meetings/${meeting_id}"
)
for path in "${resource_roots[@]}"; do
  if find_group_id_by_path "$path" >/dev/null; then
    vc_die "a disposable Keycloak resource path unexpectedly existed before the run"
  else
    lookup_status=$?
    [[ $lookup_status -eq 1 ]] || vc_die "could not safely inspect a disposable Keycloak resource path"
  fi
  printf '%s\n' "$path" >> "$owned_roots_file"
done

if ! scripts/sync-keycloak-scoped-groups.sh --env-file "$ENV_FILE" --compose-file "$COMPOSE_FILE" --manifest "$manifest_file" apply >/dev/null; then
  vc_die "could not create disposable Keycloak scoped groups"
fi
vc_pass "thirteen disposable leaf groups and their exact client-role mappings created"

while IFS= read -r path; do
  group_id="$(find_group_id_by_path "$path")" || vc_die "a disposable scoped leaf is missing"
  add_group_membership "$group_id" || vc_die "could not attach validation account to a disposable leaf"
done < <(jq -r '.groups[].path' "$manifest_file")
vc_pass "validation account attached to all disposable leaves"

if scripts/sync-keycloak-scoped-groups.sh --env-file "$ENV_FILE" --compose-file "$COMPOSE_FILE" --manifest "$manifest_file" --require-empty-memberships check >"${tmp_dir}/member-guard.out" 2>&1; then
  vc_die "empty-membership rollout guard accepted a managed leaf with a direct member"
fi
vc_pass "rollout guard rejects direct members on managed leaves"

if ! browser_login "scoped grant login"; then
  vc_die "credentialed scoped grant login failed"
fi
scanner_id="$(django_action assert_positive || true)"
if [[ ! "$scanner_id" =~ ^[1-9][0-9]*$ ]]; then
  vc_die "positive scoped relationship and provenance assertions failed"
fi
printf '%s\n' "$scanner_id" > "$scanner_id_file"
vc_pass "all twelve role families, thirteen grants, provenance, and sibling negatives verified"

if ! django_action detach >/dev/null; then
  vc_die "could not create scanner history and detach the prerequisite registration"
fi
vc_pass "scanner history created and the exact materialized registration detached"

if ! remove_all_test_memberships; then
  vc_die "could not remove every disposable leaf membership before revocation"
fi
vc_pass "validation account removed from every disposable leaf"

guard_leaf="/pgeu/series/${primary_series_id}/roles/admin"
guard_leaf_id="$(find_group_id_by_path "$guard_leaf")" || vc_die "guard test leaf is missing"
guard_child_id="$(kcadm create "groups/${guard_leaf_id}/children" -r "$keycloak_realm" -s name=scoped-smoke-guard -i 2>/dev/null | tr -d '\r\"')"
[[ -n "$guard_child_id" ]] || vc_die "could not create disposable rollout-guard child"
if scripts/sync-keycloak-scoped-groups.sh --env-file "$ENV_FILE" --compose-file "$COMPOSE_FILE" --manifest "$manifest_file" --require-empty-memberships check >"${tmp_dir}/child-guard.out" 2>&1; then
  vc_die "empty-membership rollout guard accepted a managed leaf with a child group"
fi
vc_pass "rollout guard rejects child groups below managed leaves"
kcadm delete "groups/${guard_child_id}" -r "$keycloak_realm" >/dev/null 2>&1 || vc_die "could not remove disposable rollout-guard child"
if ! scripts/sync-keycloak-scoped-groups.sh --env-file "$ENV_FILE" --compose-file "$COMPOSE_FILE" --manifest "$manifest_file" --require-empty-memberships check >/dev/null; then
  vc_die "empty-membership rollout guard did not converge after cleanup"
fi
vc_pass "rollout guard passes after memberships and descendants are absent"

if ! browser_login "scoped revocation login"; then
  vc_die "credentialed scoped revocation login failed"
fi
if ! django_action assert_revoked >/dev/null; then
  vc_die "scoped revocation, provenance, scanner-token, or history assertions failed"
fi
vc_pass "owned relations and scanner authorization revoked; collision and history preserved"

if ! django_action relink >/dev/null; then
  vc_die "registration relink unexpectedly restored authorization"
fi
if ! browser_login "post-relink convergence login"; then
  vc_die "credentialed post-relink convergence login failed"
fi
if ! django_action assert_relinked >/dev/null; then
  vc_die "relinked registration resurrected a revoked scoped relation"
fi
vc_pass "relink plus another OIDC callback does not resurrect revoked grants"

vc_pass "disposable Keycloak scoped-authorization smoke test passed"
