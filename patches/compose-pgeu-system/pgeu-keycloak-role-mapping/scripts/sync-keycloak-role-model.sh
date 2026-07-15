#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
TEMPLATE="${KEYCLOAK_REALM_TEMPLATE:-${ROOT_DIR}/services/keycloak/realm-pgeu.tmpl.json}"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/compose.yaml}"
MODE=apply

usage() {
  cat <<'USAGE'
Usage: scripts/sync-keycloak-role-model.sh [options] [apply|check|validate]

Synchronizes the PGEU client roles and owned protocol mappers in an existing
Keycloak realm. The operation does not depend on realm re-import.

Modes:
  apply     Create or update roles/mappers, then verify them. Default.
  check     Verify existing roles/mappers without changing Keycloak.
  validate  Validate the deployment-owned realm template without Keycloak.

Options:
  --env-file PATH   Runtime env file. Default: .env
  --template PATH   Realm template. Default: services/keycloak/realm-pgeu.tmpl.json
  --compose-file PATH
                    Compose file. Default: compose.yaml
  --check           Alias for check mode.

The Keycloak admin password is read only inside the Keycloak container from
/run/secrets/keycloak_admin_password and is never printed.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --template)
      TEMPLATE="$2"
      shift 2
      ;;
    --compose-file)
      COMPOSE_FILE="$2"
      shift 2
      ;;
    --check)
      MODE=check
      shift
      ;;
    apply|check|validate)
      MODE="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[XX] unknown argument: %s\n' "$1" >&2
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

read_env_value() {
  local key="$1"
  local current="${!key-}"

  if [[ -n "$current" ]]; then
    printf '%s' "$current"
    return
  fi
  [[ -f "$ENV_FILE" ]] || return 0

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

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[XX] missing required command: %s\n' "$1" >&2
    exit 1
  }
}

ENV_FILE="$(normalize_path "$ENV_FILE")"
TEMPLATE="$(normalize_path "$TEMPLATE")"
COMPOSE_FILE="$(normalize_path "$COMPOSE_FILE")"

require_command python3
require_command jq
[[ -f "$TEMPLATE" ]] || {
  printf '[XX] Keycloak realm template not found: %s\n' "$TEMPLATE" >&2
  exit 1
}

realm="$(read_env_value KEYCLOAK_REALM)"
realm="${realm:-pgeu}"
client_id="$(read_env_value PGEU_KEYCLOAK_CLIENT_ID)"
if [[ -z "$client_id" ]]; then
  client_id="$(read_env_value KEYCLOAK_CLIENT_ID)"
fi
client_id="${client_id:-pgeu}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

model_file="${tmp_dir}/role-model.json"
python3 - "$TEMPLATE" "$model_file" "$realm" "$client_id" <<'PY'
import json
import string
import sys
from pathlib import Path

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
realm = sys.argv[3]
client_id = sys.argv[4]

expected_roles = {
    "pgeu-user",
    "pgeu-superadmin",
    "pgeu-invoice-manager",
    "pgeu-news-admin",
    "pgeu-membership-admin",
    "pgeu-election-admin",
    "pgeu-accounting-manager",
    "pgeu-series-admin",
    "pgeu-conference-admin",
    "pgeu-conference-tester",
    "pgeu-conference-talkvoter",
    "pgeu-conference-staff",
    "pgeu-conference-volunteer",
    "pgeu-conference-checkin-processor",
    "pgeu-sponsor-manager",
    "pgeu-sponsor-badge-scanner",
    "pgeu-meeting-admin",
    "pgeu-wiki-viewer",
    "pgeu-wiki-editor",
}

rendered = string.Template(template_path.read_text(encoding="utf-8")).substitute(
    KEYCLOAK_REALM=realm,
    KEYCLOAK_CLIENT_ID=client_id,
    KEYCLOAK_CLIENT_SECRET="template-validation-only",
    PGEU_SITE_BASE="https://pgeu.invalid",
)
document = json.loads(rendered)
roles = document.get("roles", {}).get("client", {}).get(client_id, [])
role_names = [role.get("name") for role in roles]
if len(role_names) != len(set(role_names)):
    raise SystemExit("duplicate PGEU client role in realm template")
if set(role_names) != expected_roles:
    missing = sorted(expected_roles - set(role_names))
    extra = sorted(set(role_names) - expected_roles)
    raise SystemExit(f"PGEU client role inventory mismatch; missing={missing}; extra={extra}")
if any(not role.get("description") for role in roles):
    raise SystemExit("every PGEU client role must have a description")

clients = [client for client in document.get("clients", []) if client.get("clientId") == client_id]
if len(clients) != 1:
    raise SystemExit("realm template must contain exactly one PGEU client")
mappers = clients[0].get("protocolMappers", [])
mapper_by_name = {mapper.get("name"): mapper for mapper in mappers}
if len(mapper_by_name) != len(mappers):
    raise SystemExit("duplicate PGEU protocol mapper name in realm template")
if set(mapper_by_name) != {"pgeu-client-roles", "pgeu-group-memberships"}:
    raise SystemExit("realm template must contain exactly the two deployment-owned PGEU mappers")

role_mapper = mapper_by_name["pgeu-client-roles"]
if role_mapper.get("protocolMapper") != "oidc-usermodel-client-role-mapper":
    raise SystemExit("pgeu-client-roles uses the wrong mapper type")
role_config = role_mapper.get("config", {})
if role_config.get("claim.name") != "pgeu_roles":
    raise SystemExit("pgeu-client-roles must emit pgeu_roles")
if role_config.get("usermodel.clientRoleMapping.clientId") != client_id:
    raise SystemExit("pgeu-client-roles must read roles from the PGEU client")

group_mapper = mapper_by_name["pgeu-group-memberships"]
if group_mapper.get("protocolMapper") != "oidc-group-membership-mapper":
    raise SystemExit("pgeu-group-memberships uses the wrong mapper type")
group_config = group_mapper.get("config", {})
if group_config.get("claim.name") != "pgeu_groups":
    raise SystemExit("pgeu-group-memberships must emit pgeu_groups")
if group_config.get("full.path") != "true":
    raise SystemExit("pgeu-group-memberships must emit full group paths")

for mapper_name, mapper in mapper_by_name.items():
    config = mapper.get("config", {})
    for token_target in ("id.token.claim", "access.token.claim", "userinfo.token.claim"):
        if config.get(token_target) != "true":
            raise SystemExit(f"{mapper_name} must enable {token_target}")

output_path.write_text(
    json.dumps({"roles": roles, "mappers": mappers}, indent=2) + "\n",
    encoding="utf-8",
)
PY

printf '[OK] PGEU Keycloak role template validated (%s roles, 2 mappers)\n' \
  "$(jq '.roles | length' "$model_file")"

if [[ "$MODE" == "validate" ]]; then
  exit 0
fi

require_command docker
[[ -f "$COMPOSE_FILE" ]] || {
  printf '[XX] Compose file not found: %s\n' "$COMPOSE_FILE" >&2
  exit 1
}

compose_cmd=(docker compose)
if [[ -f "$ENV_FILE" ]]; then
  compose_cmd+=(--env-file "$ENV_FILE")
fi
compose_cmd+=(-f "$COMPOSE_FILE")

kcadm() {
  "${compose_cmd[@]}" exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@" </dev/null
}

kcadm_with_input() {
  local input_file="$1"
  shift
  "${compose_cmd[@]}" exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@" < "$input_file"
}

printf '[-] authenticating Keycloak administration session for %s/%s\n' "$realm" "$client_id"
# shellcheck disable=SC2016  # Variables expand inside the Keycloak container.
"${compose_cmd[@]}" exec -T keycloak bash -lc '
set -euo pipefail
admin_password="$(tr -d "\r\n" < /run/secrets/keycloak_admin_password)"
/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://127.0.0.1:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN" \
  --password "$admin_password" >/dev/null
' </dev/null

client_uuid="$(
  kcadm get clients \
    -r "$realm" \
    -q clientId="$client_id" \
    --fields id \
    --format csv \
    --noquotes |
  tr -d '\r' |
  tail -n 1
)"
if [[ -z "$client_uuid" || "$client_uuid" == "id" ]]; then
  printf '[XX] missing Keycloak client: %s/%s\n' "$realm" "$client_id" >&2
  exit 1
fi

apply_model() {
  local role_name role_description mapper_count mapper_index mapper_file mapper_name
  local role_list mapper_list mapper_id mapper_update
  local -a mapper_ids

  role_list="${tmp_dir}/role-list-apply.json"
  kcadm get "clients/${client_uuid}/roles" -r "$realm" -q first=0 -q max=1000 > "$role_list"
  while IFS=$'\t' read -r role_name role_description; do
    if jq -e --arg name "$role_name" '.[] | select(.name == $name)' "$role_list" >/dev/null; then
      kcadm update "clients/${client_uuid}/roles/${role_name}" \
        -r "$realm" \
        -s "description=${role_description}" >/dev/null
    else
      kcadm create "clients/${client_uuid}/roles" \
        -r "$realm" \
        -s "name=${role_name}" \
        -s "description=${role_description}" >/dev/null
    fi
  done < <(jq -r '.roles[] | [.name, .description] | @tsv' "$model_file")

  mapper_count="$(jq '.mappers | length' "$model_file")"
  for ((mapper_index = 0; mapper_index < mapper_count; mapper_index++)); do
    mapper_file="${tmp_dir}/mapper-${mapper_index}.json"
    mapper_list="${tmp_dir}/mapper-list-${mapper_index}.json"
    jq ".mappers[${mapper_index}]" "$model_file" > "$mapper_file"
    mapper_name="$(jq -r '.name' "$mapper_file")"
    kcadm get "clients/${client_uuid}/protocol-mappers/models" -r "$realm" > "$mapper_list"
    mapfile -t mapper_ids < <(jq -r --arg name "$mapper_name" '.[] | select(.name == $name) | .id' "$mapper_list")

    if [[ ${#mapper_ids[@]} -eq 0 ]]; then
      kcadm_with_input "$mapper_file" create "clients/${client_uuid}/protocol-mappers/models" \
        -r "$realm" \
        -f - >/dev/null
    else
      mapper_id="${mapper_ids[0]}"
      mapper_update="${tmp_dir}/mapper-update-${mapper_index}.json"
      jq --arg id "$mapper_id" '.id = $id' "$mapper_file" > "$mapper_update"
      kcadm_with_input "$mapper_update" update "clients/${client_uuid}/protocol-mappers/models/${mapper_id}" \
        -r "$realm" \
        -f - >/dev/null
      if [[ ${#mapper_ids[@]} -gt 1 ]]; then
        for mapper_id in "${mapper_ids[@]:1}"; do
          kcadm delete "clients/${client_uuid}/protocol-mappers/models/${mapper_id}" \
            -r "$realm" >/dev/null
        done
      fi
    fi
  done
}

verify_model() {
  local failures=0 role_name role_description actual_roles mapper_count mapper_index
  local mapper_file mapper_name mapper_list actual_mapper mapper_id
  local -a mapper_ids

  actual_roles="${tmp_dir}/role-list-verify.json"
  kcadm get "clients/${client_uuid}/roles" -r "$realm" -q first=0 -q max=1000 > "$actual_roles"
  while IFS=$'\t' read -r role_name role_description; do
    if ! jq -e --arg name "$role_name" --arg description "$role_description" \
      'any(.[]; .name == $name and .description == $description)' "$actual_roles" >/dev/null; then
      printf '[XX] Keycloak client role differs from template: %s\n' "$role_name" >&2
      failures=$((failures + 1))
    fi
  done < <(jq -r '.roles[] | [.name, .description] | @tsv' "$model_file")

  mapper_count="$(jq '.mappers | length' "$model_file")"
  mapper_list="${tmp_dir}/mapper-list-verify.json"
  kcadm get "clients/${client_uuid}/protocol-mappers/models" -r "$realm" > "$mapper_list"
  for ((mapper_index = 0; mapper_index < mapper_count; mapper_index++)); do
    mapper_file="${tmp_dir}/mapper-verify-${mapper_index}.json"
    actual_mapper="${tmp_dir}/mapper-actual-${mapper_index}.json"
    jq ".mappers[${mapper_index}]" "$model_file" > "$mapper_file"
    mapper_name="$(jq -r '.name' "$mapper_file")"
    mapfile -t mapper_ids < <(jq -r --arg name "$mapper_name" '.[] | select(.name == $name) | .id' "$mapper_list")
    if [[ ${#mapper_ids[@]} -ne 1 ]]; then
      printf '[XX] expected exactly one Keycloak mapper named %s; found %s\n' \
        "$mapper_name" "${#mapper_ids[@]}" >&2
      failures=$((failures + 1))
      continue
    fi

    mapper_id="${mapper_ids[0]}"
    kcadm get "clients/${client_uuid}/protocol-mappers/models/${mapper_id}" \
      -r "$realm" > "$actual_mapper"
    if ! jq -e --slurpfile expected "$mapper_file" '
      . as $actual |
      $expected[0] as $wanted |
      ($actual.name == $wanted.name) and
      ($actual.protocol == $wanted.protocol) and
      ($actual.protocolMapper == $wanted.protocolMapper) and
      (($actual.consentRequired // false) == ($wanted.consentRequired // false)) and
      ([
        $wanted.config | to_entries[] as $item |
        $actual.config[$item.key] == $item.value
      ] | all)
    ' "$actual_mapper" >/dev/null; then
      printf '[XX] Keycloak mapper differs from template: %s\n' "$mapper_name" >&2
      failures=$((failures + 1))
    fi
  done

  [[ "$failures" -eq 0 ]]
}

if [[ "$MODE" == "apply" ]]; then
  printf '[-] synchronizing PGEU Keycloak roles and protocol mappers\n'
  apply_model
fi

if verify_model; then
  printf '[OK] PGEU Keycloak role model %s (%s roles, 2 mappers)\n' \
    "$([[ "$MODE" == "apply" ]] && printf synchronized || printf verified)" \
    "$(jq '.roles | length' "$model_file")"
else
  printf '[XX] PGEU Keycloak role model verification failed\n' >&2
  exit 1
fi
