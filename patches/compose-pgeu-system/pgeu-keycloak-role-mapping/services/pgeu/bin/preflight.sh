#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SOURCE_DIR="${PGEU_SOURCE_DIR:-}"
SKIN_DIR="${FOSSNORTH_SKIN_SOURCE_DIR:-}"
MANIFEST="${PGEU_PATCH_MANIFEST:-${REPO_ROOT}/patches/pgeu/manifest.yaml}"
MODE="baseline"
FAILURES=0

usage() {
  cat <<'USAGE'
Usage: services/pgeu/bin/preflight.sh [--baseline|--patched]

Checks the external pgeu-system checkout without printing secret values.

Required environment:
  PGEU_SOURCE_DIR       Path to the external pgeu-system checkout.

Optional environment:
  PGEU_PATCH_MANIFEST  Patch manifest path. Defaults to patches/pgeu/manifest.yaml.
  FOSSNORTH_SKIN_SOURCE_DIR
                       Optional external fn-web skin checkout path.

Modes:
  --baseline           Require checkout HEAD to match the manifest baseline.
  --patched            Also verify the expected local dependency/OIDC patch markers.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline)
      MODE="baseline"
      shift
      ;;
    --patched)
      MODE="patched"
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

info() { printf '[-] %s\n' "$1"; }
pass() { printf '[OK] %s\n' "$1"; }
fail() { printf '[XX] %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

require_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "command available: $cmd"
  else
    fail "missing command: $cmd"
  fi
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    pass "$label"
  else
    fail "$label (missing $path)"
  fi
}

manifest_ref() {
  local path="$1"
  python3 - "$path" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
patterns = [
    r"(?im)^\s*(?:pinned_ref|baseline_ref|upstream_ref|ref|commit)\s*:\s*['\"]?([0-9a-f]{40})['\"]?\s*$",
    r"\b([0-9a-f]{40})\b",
]
for pattern in patterns:
    match = re.search(pattern, text)
    if match:
        print(match.group(1))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -qF "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_absent() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -qF "$pattern" "$file"; then
    fail "$label"
  else
    pass "$label"
  fi
}

info "checking PGEU source preflight in ${MODE} mode"
require_cmd git
require_cmd python3

if [[ -z "$SOURCE_DIR" ]]; then
  fail "PGEU_SOURCE_DIR is set"
else
  [[ -d "$SOURCE_DIR" ]] && pass "PGEU_SOURCE_DIR exists" || fail "PGEU_SOURCE_DIR exists"
fi

if [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR" ]]; then
  require_file "${SOURCE_DIR}/manage.py" "upstream manage.py exists"
  require_file "${SOURCE_DIR}/postgresqleu/settings.py" "upstream Django settings exists"
  require_file "${SOURCE_DIR}/postgresqleu/oauthlogin/oauthclient.py" "upstream OAuth client exists"
  require_file "${SOURCE_DIR}/postgresqleu/oauthlogin/views.py" "upstream OAuth views exists"
  require_file "${SOURCE_DIR}/tools/devsetup/dev_requirements.txt" "upstream requirements file exists"

  if git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    pass "PGEU_SOURCE_DIR is a Git worktree"
  else
    fail "PGEU_SOURCE_DIR is a Git worktree"
  fi
fi

if [[ -f "$MANIFEST" ]]; then
  pass "patch manifest exists"
  if expected_ref="$(manifest_ref "$MANIFEST")"; then
    pass "manifest baseline ref parsed"
    if [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR" ]] && actual_ref="$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null)"; then
      if [[ "$actual_ref" == "$expected_ref" ]]; then
        pass "checkout HEAD matches manifest baseline"
      else
        fail "checkout HEAD does not match manifest baseline"
      fi
    fi
  else
    fail "manifest contains a parseable 40-character baseline ref"
  fi
else
  fail "patch manifest exists at $MANIFEST"
fi

if [[ "$MODE" == "patched" && -n "$SOURCE_DIR" && -d "$SOURCE_DIR" ]]; then
  REQ_FILE="${SOURCE_DIR}/tools/devsetup/dev_requirements.txt"
  OAUTH_FILE="${SOURCE_DIR}/postgresqleu/oauthlogin/oauthclient.py"
  OAUTH_VIEWS_FILE="${SOURCE_DIR}/postgresqleu/oauthlogin/views.py"
  ROLE_SYNC_FILE="${SOURCE_DIR}/postgresqleu/oauthlogin/rolesync.py"
  ROLE_SYNC_TEST_FILE="${SOURCE_DIR}/postgresqleu/oauthlogin/tests.py"
  UTIL_MODEL_FILE="${SOURCE_DIR}/postgresqleu/util/models.py"
  ROLE_GRANT_MIGRATION="${SOURCE_DIR}/postgresqleu/util/migrations/0009_keycloakrolegrant.py"
  EXPECTED_UNIQUE_CONSTRAINTS="${SOURCE_DIR}/postgresqleu/util/migrations/expected_unique_constraints.csv"
  EXPECTED_FOREIGN_CONSTRAINTS="${SOURCE_DIR}/postgresqleu/util/migrations/expected_foreign_constraints.csv"
  WIKI_VIEW_FILE="${SOURCE_DIR}/postgresqleu/confwiki/views.py"
  WIKI_TEST_FILE="${SOURCE_DIR}/postgresqleu/confwiki/tests.py"

  check_contains "$REQ_FILE" "pycryptodomex==3.19.1" "dependency pin present: pycryptodomex==3.19.1"
  check_contains "$REQ_FILE" "qrcode==7.4.2" "dependency pin present: qrcode==7.4.2"
  check_contains "$REQ_FILE" "cairosvg==2.7.1" "dependency pin present: cairosvg==2.7.1"
  check_contains "$REQ_FILE" "PyMuPDF==1.24.9" "dependency pin present: PyMuPDF==1.24.9"
  check_contains "$OAUTH_FILE" "def oauth_login_keycloak" "Keycloak OAuth handler present"
  check_contains "$OAUTH_FILE" "oauth_keycloak_id_token" "Keycloak ID token stored for OIDC logout hint"
  check_contains "$OAUTH_FILE" "KEYCLOAK_ACCESS_ROLES" "Keycloak accepted PGEU role set present"
  check_contains "$OAUTH_FILE" "_validated_keycloak_profile" "Keycloak verified-email profile guard present"
  check_contains "$OAUTH_FILE" "email_verified" "Keycloak verified-email claim required"
  check_contains "$OAUTH_FILE" "protocol/openid-connect/userinfo" "authenticated Keycloak userinfo endpoint used"
  check_contains "$OAUTH_FILE" "_validated_keycloak_profile(r, base)" "Keycloak authorization claims come from userinfo"
  check_contains "$OAUTH_FILE" "_keycloak_string_list_claim(profile, 'pgeu_roles')" "Keycloak pgeu_roles shape is fail-closed"
  check_contains "$OAUTH_FILE" "_keycloak_string_list_claim(profile, 'pgeu_groups')" "Keycloak pgeu_groups shape is fail-closed"
  check_contains "$OAUTH_FILE" "Keycloak did not provide a valid subject identifier" "Keycloak subject is required"
  check_absent "$OAUTH_FILE" "_decode_jwt_payload" "unverified JWT payload is not used for authorization"
  check_contains "$OAUTH_FILE" "_sync_keycloak_roles" "global Keycloak role convergence remains present"
  check_contains "$OAUTH_FILE" "sync_keycloak_scoped_roles" "scoped Keycloak role sync invocation present"
  check_contains "$OAUTH_FILE" "get_or_bind_keycloak_user" "Keycloak subject binding invocation present"
  check_contains "$OAUTH_FILE" "get_keycloak_revocation_target" "roleless callback revocation target lookup present"
  check_contains "$OAUTH_FILE" "_converge_denied_keycloak_identity" "denied and conflicting callbacks converge empty intent"
  check_contains "$OAUTH_FILE" "sync_keycloak_scoped_roles(binding, set(), set())" "roleless callback revokes owned scoped grants"
  check_contains "$OAUTH_FILE" "Your account is not enabled for PGEU access." "Keycloak login rejection for missing PGEU role present"
  require_file "$ROLE_SYNC_FILE" "Keycloak scoped role-sync module exists"
  require_file "$ROLE_SYNC_TEST_FILE" "Keycloak role-sync unit tests exist"
  require_file "$ROLE_GRANT_MIGRATION" "Keycloak grant provenance migration exists"
  require_file "$EXPECTED_UNIQUE_CONSTRAINTS" "expected unique-constraint inventory exists"
  require_file "$EXPECTED_FOREIGN_CONSTRAINTS" "expected foreign-constraint inventory exists"
  require_file "$WIKI_TEST_FILE" "wiki edit authorization unit test exists"
  check_contains "$OAUTH_FILE" "KEYCLOAK_GROUP_ROLES" "Keycloak manager role mapping present"
  check_contains "$ROLE_SYNC_FILE" "KEYCLOAK_SCOPED_ROLES" "Keycloak scoped role inventory present"
  check_contains "$ROLE_SYNC_FILE" "_parse_keycloak_group_path" "exact Keycloak group path parser present"
  check_contains "$ROLE_SYNC_FILE" "/pgeu/series/" "series-scoped Keycloak path present"
  check_contains "$ROLE_SYNC_FILE" "/pgeu/conferences/" "conference-scoped Keycloak paths present"
  check_contains "$ROLE_SYNC_FILE" "/pgeu/sponsors/" "sponsor-scoped Keycloak paths present"
  check_contains "$ROLE_SYNC_FILE" "/pgeu/meetings/" "meeting-scoped Keycloak path present"
  check_contains "$ROLE_SYNC_FILE" "_active_registration" "registration relationship prerequisite present"
  check_contains "$ROLE_SYNC_FILE" "if not user.is_active" "inactive Django users fail closed"
  check_contains "$ROLE_SYNC_FILE" "email__iexact=email" "verified-email account lookup is case-insensitive"
  check_contains "$ROLE_SYNC_FILE" "if user_binding is not None" "migration fallback excludes users bound to another subject"
  check_contains "$ROLE_SYNC_FILE" "Member.objects.filter(user=user)" "member relationship prerequisite present"
  check_contains "$ROLE_SYNC_FILE" "sponsor.confirmed" "confirmed sponsor badge-scanner prerequisite present"
  check_contains "$ROLE_SYNC_FILE" "SponsorClaimedBenefit.objects.filter" "claimed badge-scanning benefit prerequisite present"
  check_contains "$ROLE_SYNC_FILE" "generate_random_token()" "safe badge-scanner token generation present"
  check_contains "$ROLE_SYNC_FILE" "scanner_id=relation_pk" "badge-scanner revocation uses stored registration identity"
  check_contains "$ROLE_SYNC_FILE" "pk=relation_record_pk" "badge-scanner revocation uses exact stored scanner row"
  check_contains "$ROLE_SYNC_FILE" "historical scans are retained" "badge-scanner revocation retention warning present"
  check_contains "$ROLE_SYNC_FILE" "_plan_keycloak_grant_sync" "Keycloak grant reconciliation planner present"
  check_contains "$ROLE_SYNC_TEST_FILE" "KeycloakDeniedCallbackConvergenceTests" "roleless callback convergence regression tests present"
  check_contains "$ROLE_SYNC_TEST_FILE" "test_unbound_migration_window_user_loses_global_grants_without_binding" "pre-binding global revocation regression test present"
  check_contains "$ROLE_SYNC_TEST_FILE" "test_different_subject_cannot_downgrade_email_matched_bound_user" "cross-subject downgrade regression test present"
  check_contains "$ROLE_SYNC_TEST_FILE" "test_inactive_bound_user_converges_empty_before_accepted_role_is_denied" "inactive bound-user convergence regression test present"
  check_contains "$ROLE_SYNC_TEST_FILE" "test_exact_bound_email_conflict_converges_bound_user_only" "exact-bound identity-conflict convergence test present"
  check_contains "$ROLE_SYNC_TEST_FILE" "test_detached_registration_relations_are_revoked_by_stored_identity" "detached registration revocation test present"
  check_contains "$ROLE_SYNC_TEST_FILE" "test_detached_scanner_token_is_revoked_and_scan_history_is_retained" "detached scanner history-retention test present"
  check_contains "$ROLE_SYNC_TEST_FILE" "test_replacement_scanner_row_is_not_deleted_by_old_owned_ledger" "replacement scanner ownership test present"
  check_contains "$UTIL_MODEL_FILE" "class KeycloakIdentityBinding" "Keycloak identity binding model present"
  check_contains "$UTIL_MODEL_FILE" "('issuer', 'subject')" "Keycloak issuer-subject uniqueness present"
  check_contains "$UTIL_MODEL_FILE" "('issuer', 'user')" "Keycloak issuer-user uniqueness present"
  check_contains "$UTIL_MODEL_FILE" "class KeycloakRoleGrant" "Keycloak scoped grant provenance model present"
  check_contains "$UTIL_MODEL_FILE" "client_role = models.CharField" "Keycloak scoped grant client-role provenance present"
  check_contains "$UTIL_MODEL_FILE" "group_path = models.CharField" "Keycloak scoped grant path provenance present"
  check_contains "$UTIL_MODEL_FILE" "relation_target = models.CharField" "Keycloak exact relationship target provenance present"
  check_contains "$UTIL_MODEL_FILE" "relation_record = models.CharField" "Keycloak exact relationship row provenance present"
  check_contains "$UTIL_MODEL_FILE" "owned = models.BooleanField" "Keycloak grant ownership marker present"
  check_contains "$UTIL_MODEL_FILE" "created_at = models.DateTimeField" "Keycloak provenance creation timestamp present"
  check_contains "$UTIL_MODEL_FILE" "last_seen_at = models.DateTimeField" "Keycloak provenance last-seen timestamp present"
  check_contains "$EXPECTED_UNIQUE_CONSTRAINTS" "util_keycloakidentitybinding_issuer_subject_e1b30fd6_uniq" "identity subject unique constraint is inventoried"
  check_contains "$EXPECTED_UNIQUE_CONSTRAINTS" "util_keycloakidentitybinding_issuer_user_id_e0ff1763_uniq" "identity user unique constraint is inventoried"
  check_contains "$EXPECTED_UNIQUE_CONSTRAINTS" "util_keycloakrolegrant_binding_id_client_role_g_78273c51_uniq" "scoped grant unique constraint is inventoried"
  check_contains "$EXPECTED_FOREIGN_CONSTRAINTS" "util_keycloakidentitybinding_user_id_f0d1acb8_fk_auth_user_id" "identity user foreign key is inventoried"
  check_contains "$EXPECTED_FOREIGN_CONSTRAINTS" "util_keycloakrolegra_binding_id_7542bb48_fk_util_keyc" "scoped grant binding foreign key is inventoried"
  check_contains "$WIKI_VIEW_FILE" "_check_wiki_permissions(request, page, readwrite=True)" "wiki edit view requires write permission"
  check_contains "$OAUTH_VIEWS_FILE" "django_logout(request)" "OAuth logout GET compatibility present"
  check_contains "$OAUTH_VIEWS_FILE" "id_token_hint" "OAuth logout sends Keycloak ID token hint when available"
  check_contains "$OAUTH_VIEWS_FILE" "protocol/openid-connect/logout" "OAuth logout redirects through Keycloak end-session endpoint"
fi

if [[ -n "$SKIN_DIR" ]]; then
  info "checking Foss North skin checkout"
  if [[ -d "$SKIN_DIR" ]]; then
    pass "FOSSNORTH_SKIN_SOURCE_DIR exists"
    require_file "${SKIN_DIR}/template/base.html" "skin Django base template exists"
    require_file "${SKIN_DIR}/template.jinja/base.html" "skin Jinja base template exists"
    require_file "${SKIN_DIR}/media/css/style.css" "skin stylesheet exists"
    require_file "${SKIN_DIR}/media/img/logo-black.png" "skin logo exists"
    require_file "${SKIN_DIR}/code/skin_settings.py" "skin settings exists"
    if git -C "$SKIN_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      pass "FOSSNORTH_SKIN_SOURCE_DIR is a Git worktree"
      if [[ "$(git -C "$SKIN_DIR" rev-parse --abbrev-ref HEAD)" == "prod" ]]; then
        pass "Foss North skin checkout is on prod branch"
      else
        fail "Foss North skin checkout is on prod branch"
      fi
    else
      fail "FOSSNORTH_SKIN_SOURCE_DIR is a Git worktree"
    fi
  else
    fail "FOSSNORTH_SKIN_SOURCE_DIR exists"
  fi
fi

if [[ $FAILURES -eq 0 ]]; then
  pass "PGEU preflight passed"
else
  printf '[XX] PGEU preflight failed with %s issue(s)\n' "$FAILURES" >&2
  exit 1
fi
