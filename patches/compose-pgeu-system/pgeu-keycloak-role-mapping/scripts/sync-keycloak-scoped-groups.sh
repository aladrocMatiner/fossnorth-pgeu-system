#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
MANIFEST="${KEYCLOAK_SCOPED_GROUPS_MANIFEST:-}"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/compose.yaml}"
MODE=apply
REQUIRE_EMPTY_MEMBERSHIPS=false

usage() {
  cat <<'USAGE'
Usage: scripts/sync-keycloak-scoped-groups.sh [options] [apply|check|validate]

Creates or verifies only the scoped Keycloak group paths declared by a
secret-safe inventory manifest, and assigns pgeu-user plus the matching generic
PGEU client role to each leaf group. It never changes user memberships and
never invents scope identifiers.

Manifest shape:
  {"version": 1, "groups": [{"path": "/pgeu/.../roles/...", "client_role": "pgeu-..."}]}

Modes:
  apply     Ensure group paths and leaf client-role mappings, then verify. Default.
  check     Verify declared paths and role mappings without changing Keycloak.
  validate  Validate and normalize the manifest without contacting Keycloak.

Options:
  --env-file PATH   Runtime env file. Default: .env
  --manifest PATH   Inventory manifest. Defaults to KEYCLOAK_SCOPED_GROUPS_MANIFEST.
  --compose-file PATH
                    Compose file. Default: compose.yaml
  --check           Alias for check mode.
  --require-empty-memberships
                    Fail when a managed leaf has direct user members or child
                    groups. This is a read-only rollout guard and never changes
                    memberships or hierarchy.

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
    --manifest)
      MANIFEST="$2"
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
    --require-empty-memberships)
      REQUIRE_EMPTY_MEMBERSHIPS=true
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
COMPOSE_FILE="$(normalize_path "$COMPOSE_FILE")"

if [[ -z "$MANIFEST" ]]; then
  MANIFEST="$(read_env_value KEYCLOAK_SCOPED_GROUPS_MANIFEST)"
fi
if [[ -z "$MANIFEST" && "$MODE" == "validate" ]]; then
  MANIFEST="services/keycloak/scoped-groups.example.json"
fi
if [[ -z "$MANIFEST" ]]; then
  printf '[XX] --manifest or KEYCLOAK_SCOPED_GROUPS_MANIFEST is required\n' >&2
  exit 1
fi
MANIFEST="$(normalize_path "$MANIFEST")"

require_command python3
require_command jq
[[ -f "$MANIFEST" ]] || {
  printf '[XX] scoped-group manifest not found: %s\n' "$MANIFEST" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

normalized_manifest="${tmp_dir}/scoped-groups.tsv"
python3 - "$MANIFEST" "$normalized_manifest" <<'PY'
import json
import re
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

try:
    document = json.loads(manifest_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"invalid scoped-group manifest: {exc}")

if not isinstance(document, dict) or set(document) != {"version", "groups"}:
    raise SystemExit("manifest must contain exactly version and groups")
if isinstance(document["version"], bool) or document["version"] != 1:
    raise SystemExit("manifest version must be integer 1")
if not isinstance(document["groups"], list):
    raise SystemExit("manifest groups must be a list")

conference_id = r"[a-z0-9_]+"
wiki_id = r"[A-Za-z0-9_-]+"
numeric_id = r"[1-9][0-9]*"

rules = [
    (
        re.compile(rf"^/pgeu/series/{numeric_id}/roles/admin$"),
        {"admin": "pgeu-series-admin"},
    ),
    (
        re.compile(
            rf"^/pgeu/conferences/{conference_id}/roles/"
            r"(admin|tester|talkvoter|staff|volunteer|checkin-processor)$"
        ),
        {
            "admin": "pgeu-conference-admin",
            "tester": "pgeu-conference-tester",
            "talkvoter": "pgeu-conference-talkvoter",
            "staff": "pgeu-conference-staff",
            "volunteer": "pgeu-conference-volunteer",
            "checkin-processor": "pgeu-conference-checkin-processor",
        },
    ),
    (
        re.compile(
            rf"^/pgeu/conferences/{conference_id}/wiki/{wiki_id}/roles/(viewer|editor)$"
        ),
        {
            "viewer": "pgeu-wiki-viewer",
            "editor": "pgeu-wiki-editor",
        },
    ),
    (
        re.compile(rf"^/pgeu/sponsors/{numeric_id}/roles/(manager|badge-scanner)$"),
        {
            "manager": "pgeu-sponsor-manager",
            "badge-scanner": "pgeu-sponsor-badge-scanner",
        },
    ),
    (
        re.compile(rf"^/pgeu/meetings/{numeric_id}/roles/admin$"),
        {"admin": "pgeu-meeting-admin"},
    ),
]

normalized = []
seen_paths = set()
for index, entry in enumerate(document["groups"]):
    if not isinstance(entry, dict) or set(entry) != {"path", "client_role"}:
        raise SystemExit(f"groups[{index}] must contain exactly path and client_role")
    path = entry["path"]
    client_role = entry["client_role"]
    if not isinstance(path, str) or not isinstance(client_role, str):
        raise SystemExit(f"groups[{index}] path and client_role must be strings")
    if path in seen_paths:
        raise SystemExit(f"duplicate scoped group path: {path}")

    expected_role = None
    for pattern, role_map in rules:
        match = pattern.fullmatch(path)
        if match:
            leaf_role = match.group(1) if match.lastindex else "admin"
            expected_role = role_map[leaf_role]
            break
    if expected_role is None:
        raise SystemExit(f"non-canonical or incomplete scoped group path: {path}")
    if client_role != expected_role:
        raise SystemExit(
            f"scoped group role mismatch for {path}: expected {expected_role}, got {client_role}"
        )

    seen_paths.add(path)
    normalized.append((path, client_role))

normalized.sort()
output_path.write_text(
    "".join(f"{path}\t{client_role}\n" for path, client_role in normalized),
    encoding="utf-8",
)
PY

group_count="$(wc -l < "$normalized_manifest" | tr -d '[:space:]')"
printf '[OK] scoped-group manifest validated (%s leaf groups)\n' "$group_count"

if [[ "$MODE" == "validate" || "$group_count" == "0" ]]; then
  exit 0
fi

require_command docker
[[ -f "$COMPOSE_FILE" ]] || {
  printf '[XX] Compose file not found: %s\n' "$COMPOSE_FILE" >&2
  exit 1
}

realm="$(read_env_value KEYCLOAK_REALM)"
realm="${realm:-pgeu}"
client_id="$(read_env_value PGEU_KEYCLOAK_CLIENT_ID)"
if [[ -z "$client_id" ]]; then
  client_id="$(read_env_value KEYCLOAK_CLIENT_ID)"
fi
client_id="${client_id:-pgeu}"

compose_cmd=(docker compose)
if [[ -f "$ENV_FILE" ]]; then
  compose_cmd+=(--env-file "$ENV_FILE")
fi
compose_cmd+=(-f "$COMPOSE_FILE")

kcadm() {
  "${compose_cmd[@]}" exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@" </dev/null
}

printf '[-] authenticating Keycloak administration session for scoped groups in %s/%s\n' \
  "$realm" "$client_id"
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

scoped_roles=(
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

mapfile -t manifest_roles < <(
  {
    printf '%s\n' pgeu-user
    cut -f2 "$normalized_manifest"
  } | sort -u
)
for role_name in "${manifest_roles[@]}"; do
  if ! kcadm get "clients/${client_uuid}/roles/${role_name}" -r "$realm" >/dev/null 2>&1; then
    printf '[XX] scoped manifest requires missing client role: %s\n' "$role_name" >&2
    printf '     Run scripts/sync-keycloak-role-model.sh apply first.\n' >&2
    exit 1
  fi
done

child_id=""
declare -A group_id_cache=()
find_child_id() {
  local parent_id="$1"
  local child_name="$2"
  local list_file="${tmp_dir}/children-$RANDOM.json"
  local -a matching_ids

  if [[ -z "$parent_id" ]]; then
    kcadm get groups -r "$realm" -q first=0 -q max=10000 > "$list_file"
  else
    kcadm get "groups/${parent_id}/children" -r "$realm" -q first=0 -q max=10000 > "$list_file"
  fi
  mapfile -t matching_ids < <(
    jq -r --arg name "$child_name" '.[] | select(.name == $name) | .id' "$list_file"
  )
  if [[ ${#matching_ids[@]} -gt 1 ]]; then
    printf '[XX] duplicate Keycloak child groups named %s under managed hierarchy\n' \
      "$child_name" >&2
    exit 1
  fi
  child_id="${matching_ids[0]:-}"
}

resolved_group_id=""
ensure_group_path() {
  local path="$1"
  local parent_id=""
  local current_path=""
  local segment created_id endpoint
  local -a segments

  IFS='/' read -r -a segments <<< "${path#/}"
  for segment in "${segments[@]}"; do
    current_path="${current_path}/${segment}"
    if [[ -n "${group_id_cache[$current_path]+present}" ]]; then
      child_id="${group_id_cache[$current_path]}"
    else
      find_child_id "$parent_id" "$segment"
      if [[ -z "$child_id" ]]; then
        if [[ "$MODE" == "check" ]]; then
          printf '[XX] missing declared Keycloak group path: %s\n' "$current_path" >&2
          return 1
        fi
        if [[ -z "$parent_id" ]]; then
          endpoint=groups
        else
          endpoint="groups/${parent_id}/children"
        fi
        created_id="$(
          kcadm create "$endpoint" -r "$realm" -s "name=${segment}" -i |
          tr -d '\r"'
        )"
        if [[ -z "$created_id" ]]; then
          printf '[XX] Keycloak did not return an id for created group: %s\n' \
            "$current_path" >&2
          return 1
        fi
        child_id="$created_id"
        printf '[OK] created Keycloak group: %s\n' "$current_path"
      fi
      group_id_cache["$current_path"]="$child_id"
    fi
    parent_id="$child_id"
  done
  resolved_group_id="$parent_id"
}

array_contains() {
  local needle="$1"
  shift
  local value

  for value in "$@"; do
    [[ "$value" == "$needle" ]] && return 0
  done
  return 1
}

is_scoped_role() {
  array_contains "$1" "${scoped_roles[@]}"
}

check_empty_memberships() {
  local path="$1"
  local members_file="${tmp_dir}/members-$RANDOM.json"
  local children_file="${tmp_dir}/children-rollout-$RANDOM.json"
  local child_count member_count

  if [[ "$REQUIRE_EMPTY_MEMBERSHIPS" != "true" ]]; then
    return 0
  fi

  kcadm get "groups/${resolved_group_id}/members" \
    -r "$realm" \
    -q first=0 \
    -q max=10000 > "$members_file"
  member_count="$(jq 'length' "$members_file")"
  if [[ "$member_count" != "0" ]]; then
    printf '[XX] scoped leaf group must have zero direct members for rollout: %s (count=%s)\n' \
      "$path" "$member_count" >&2
    return 1
  fi

  kcadm get "groups/${resolved_group_id}/children" \
    -r "$realm" \
    -q first=0 \
    -q max=10000 > "$children_file"
  child_count="$(jq 'length' "$children_file")"
  if [[ "$child_count" != "0" ]]; then
    printf '[XX] scoped rollout leaf must not contain child groups: %s (count=%s)\n' \
      "$path" "$child_count" >&2
    return 1
  fi
  printf '[OK] scoped leaf group has zero direct members: %s\n' "$path"
  printf '[OK] scoped leaf group has zero child groups: %s\n' "$path"
}

sync_leaf_role() {
  local path="$1"
  local desired_role="$2"
  local mappings_file="${tmp_dir}/mappings-$RANDOM.json"
  local verify_file="${tmp_dir}/mappings-verify-$RANDOM.json"
  local mapped_role expected_role
  local -a mapped_pgeu_roles verified_pgeu_roles

  kcadm get "groups/${resolved_group_id}/role-mappings/clients/${client_uuid}" \
    -r "$realm" > "$mappings_file"
  mapfile -t mapped_pgeu_roles < <(
    jq -r '.[].name | select(startswith("pgeu-"))' "$mappings_file"
  )

  for mapped_role in "${mapped_pgeu_roles[@]}"; do
    if [[ "$mapped_role" == "pgeu-user" || "$mapped_role" == "$desired_role" ]]; then
      continue
    fi
    if ! is_scoped_role "$mapped_role"; then
      printf '[XX] refusing to alter unexpected global or unknown PGEU role on leaf group: %s (%s)\n' \
        "$path" "$mapped_role" >&2
      return 1
    fi
  done

  for expected_role in pgeu-user "$desired_role"; do
    if ! array_contains "$expected_role" "${mapped_pgeu_roles[@]}"; then
      if [[ "$MODE" == "check" ]]; then
        printf '[XX] leaf group is missing client role %s: %s\n' \
          "$expected_role" "$path" >&2
        return 1
      fi
      kcadm add-roles \
        -r "$realm" \
        --gid "$resolved_group_id" \
        --cclientid "$client_id" \
        --rolename "$expected_role" >/dev/null
    fi
  done

  for mapped_role in "${mapped_pgeu_roles[@]}"; do
    if [[ "$mapped_role" != "pgeu-user" && "$mapped_role" != "$desired_role" ]]; then
      if [[ "$MODE" == "check" ]]; then
        printf '[XX] leaf group has unexpected scoped client role %s: %s\n' \
          "$mapped_role" "$path" >&2
        return 1
      fi
      kcadm remove-roles \
        -r "$realm" \
        --gid "$resolved_group_id" \
        --cclientid "$client_id" \
        --rolename "$mapped_role" >/dev/null
    fi
  done

  kcadm get "groups/${resolved_group_id}/role-mappings/clients/${client_uuid}" \
    -r "$realm" > "$verify_file"
  mapfile -t verified_pgeu_roles < <(
    jq -r '.[].name | select(startswith("pgeu-"))' "$verify_file"
  )
  for expected_role in pgeu-user "$desired_role"; do
    if ! array_contains "$expected_role" "${verified_pgeu_roles[@]}"; then
      printf '[XX] failed to map client role %s to leaf group: %s\n' \
        "$expected_role" "$path" >&2
      return 1
    fi
  done
  for mapped_role in "${verified_pgeu_roles[@]}"; do
    if [[ "$mapped_role" != "pgeu-user" && "$mapped_role" != "$desired_role" ]]; then
      printf '[XX] unexpected PGEU client role remains on leaf group: %s (%s)\n' \
        "$path" "$mapped_role" >&2
      return 1
    fi
  done
}

while IFS=$'\t' read -r group_path client_role; do
  if ! ensure_group_path "$group_path"; then
    exit 1
  fi
  if ! check_empty_memberships "$group_path"; then
    exit 1
  fi
  if ! sync_leaf_role "$group_path" "$client_role"; then
    exit 1
  fi
  printf '[OK] scoped leaf group %s client roles (pgeu-user + %s): %s\n' \
    "$([[ "$MODE" == "apply" ]] && printf synchronized || printf verified)" \
    "$client_role" \
    "$group_path"
done < "$normalized_manifest"

printf '[OK] Keycloak scoped-group manifest %s (%s leaf groups; user memberships untouched)\n' \
  "$([[ "$MODE" == "apply" ]] && printf applied || printf verified)" \
  "$group_count"
