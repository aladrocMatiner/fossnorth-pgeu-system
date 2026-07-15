# PGEU Patch Overlay

This directory records every local change applied on top of upstream
`pgeu-system`.

The current baseline is:

- Repository: `https://github.com/pgeu/pgeu-system.git`
- Pinned ref: `b0f05c327012e41a34ad9b25d64b7918839461c4`
- Checked date: `2026-06-30`

The baseline must not float to upstream `master`. Moving to a new release, tag,
or commit requires a separate OpenSpec change that updates
`patches/pgeu/manifest.yaml`, reapplies the overlay to a clean checkout, records
conflicts or removals, and validates the integrated stack.

The current manifest inventory contains six ordered patches: Keycloak/OIDC
dependencies, Django 5/OIDC logout, coarse role sync, verified-email hardening,
scoped object-role sync with provenance, and the wiki edit authorization guard.

## Apply

Use one entrypoint from the repository root:

```bash
scripts/apply-pgeu-patches.sh "${PGEU_SOURCE_DIR}"
```

The script verifies that the target is a Git checkout at the manifest baseline,
applies patch entries in manifest order, and prints `git diff --stat` plus
`git diff --check` output for review.

## Current Patches

### `001-keycloak-oidc-dependencies.patch`

Purpose: enable PGEU to use the deployment-owned confidential Keycloak OIDC
client, preserve the ID token needed for RP-initiated logout, and keep
dependency installation reproducible in the container runtime.

Upstream files changed:

- `tools/devsetup/dev_requirements.txt`
- `postgresqleu/oauthlogin/oauthclient.py`

Readiness: `split-required`. The patch currently mixes three decisions:

- Keycloak/OIDC provider support, which can be a deployment-neutral upstream PR
  if it follows the existing OAuth provider pattern.
- OIDC ID token capture, which should travel with a generic provider logout
  hook or RP-initiated logout PR.
- Dependency pin changes, which should remain local unless upstream needs the
  same runtime package versions independently.

Do not submit this patch upstream as one unit.

### `002-oauth-logout-get-compat.patch`

Purpose: keep PGEU's existing `/accounts/logout` link working with Django 5 and
terminate the Keycloak SSO session. PGEU templates currently use a GET link,
while Django's built-in logout view now rejects GET with HTTP 405. A local-only
Django logout is not enough for this deployment because the browser would keep
the Keycloak SSO cookie and the next login would silently authenticate again.
When a Keycloak ID token is present in the Django session, the patch sends it as
`id_token_hint` so Keycloak completes RP-initiated logout without stopping on an
interactive confirmation page.

Upstream files changed:

- `postgresqleu/oauthlogin/views.py`

Readiness: `split-required`. The Django 5 GET logout compatibility issue is
upstream-relevant, but upstream may prefer replacing logout links with POST
forms. The Keycloak end-session redirect is OIDC-provider behavior and should be
implemented behind a generic provider logout hook rather than hard-coded in the
view. Do not submit the current combined patch upstream as one unit.

### `003-keycloak-role-sync.patch`

Purpose: require an accepted PGEU role from Keycloak and synchronize
Keycloak-owned coarse authorization into Django during login.

Upstream files changed:

- `postgresqleu/oauthlogin/oauthclient.py`

Readiness: `plugin-candidate`. The patch keeps the logic intentionally narrow:
`pgeu-user` allows normal login, `pgeu-superadmin` maps to Django `is_staff` and
`is_superuser`, and manager roles map to deployment-owned Django groups. When a
role is removed in Keycloak, the next login removes the corresponding
Keycloak-owned flag or group. PGEU object-level assignments and unrelated Django
groups remain local to PGEU.

This patch should move to a PGEU plugin or hook if the upstream project exposes
one. Until then it remains tied to the pinned baseline in `manifest.yaml`.

### `004-keycloak-verified-email.patch`

Purpose: reject Keycloak account linking/login unless userinfo contains a
non-empty email and `email_verified` is exactly `true`.

Upstream file changed:

- `postgresqleu/oauthlogin/oauthclient.py`

Readiness: `pull-request-candidate`. This is provider-neutral OIDC
account-linking defense in depth and is deliberately separate from the Foss
North scoped-role model. Remove it only when upstream provides equivalent
verified-email enforcement.

### `005-keycloak-scoped-role-sync.patch`

Purpose: require a matching fixed scoped client role plus exact `pgeu_groups`
path, validate local prerequisites, materialize only the allowlisted PGEU object
relation, and record whether that relation is owned by Keycloak sync.

Upstream files changed:

- `postgresqleu/oauthlogin/oauthclient.py`
- `postgresqleu/oauthlogin/rolesync.py`
- `postgresqleu/oauthlogin/tests.py`
- `postgresqleu/util/models.py`
- `postgresqleu/util/migrations/0009_keycloakrolegrant.py`
- `postgresqleu/util/migrations/expected_unique_constraints.csv`
- `postgresqleu/util/migrations/expected_foreign_constraints.csv`

Readiness: `plugin-candidate`. `KeycloakIdentityBinding` persists exact
issuer/subject identity for the Django user. The scoped-only
`KeycloakRoleGrant` records binding, client role, canonical group path, grant
type, resource `target`, exact materialized `relation_target`, optional exact
scanner-row `relation_record`, `owned`, and timestamps. A pre-existing relation
is recorded as `owned=false` and preserved on later revocation; a relation
created by sync is `owned=true` and may be removed when its matching grant
disappears on the next authenticated Keycloak callback. Exact stored relation
identities allow revocation after a registration is detached from its user and
allow scanner revocation to remove only the recorded `SponsorScanner` row while
preserving `ScannedAttendee` history. A later local replacement scanner row is
preserved as unowned.

For an exact existing issuer/subject binding, a roleless, inactive-user, or
verified-email identity-conflict callback converges that exact user's global
and owned scoped intent to empty before returning `403`; it never creates a
user, binding, or Django session. During the pre-binding migration window, one
genuinely unbound case-insensitive verified-email user match has only global
intent cleared. Unknown, ambiguous, and differently-bound fallback identities
are denied without mutation. The implementation has no out-of-band reconcile
command and does not invalidate active Django sessions. Those limits are
documented in
[`docs/Areas/PGEU Authorization.md`](../../docs/Areas/PGEU%20Authorization.md)
and block production person assignments in the current structural-only rollout.

Run migrations and `python manage.py djangoconstraints_apply` before accepting
a login with the scoped patch. The two expected-constraint inventories cover
the three new uniqueness rules and two foreign keys. Those CSV inventories
belong to this pinned overlay and must be regenerated and revalidated whenever
the upstream baseline moves. The role/path grammar and
registration/member/sponsor/wiki prerequisites fail closed without creating
business prerequisites. Badge-scanner revocation removes only the exact owned
`SponsorScanner`; scan history remains.

Validation on PostgreSQL 16 passed the migration and all 37 focused OAuth/wiki
tests. The upstream constraint auditor still reports 48 PostgreSQL-catalog
false positives and 38 inherited application-inventory mismatches; none names
the five constraints added by this patch. Do not describe that global upstream
audit as clean.

### `006-confwiki-edit-authorization.patch`

Purpose: make the attendee wiki edit view call its existing permission helper
with `readwrite=True`, closing the direct edit URL for a read-only attendee.

Upstream files changed:

- `postgresqleu/confwiki/views.py`
- `postgresqleu/confwiki/tests.py`

Readiness: `pull-request-candidate`. The included regression test proves a
read-only attendee cannot open the direct edit view or publish by direct POST,
and that denial leaves form/history creation and page contents unchanged. It
also covers explicit-editor GET plus the public-editor and editor-registration-
type write checks. The active OpenSpec still requires a positive editor
preview/commit regression and history/view non-regression coverage before any
production wiki membership is authorized.

## Extension-Point Findings At The Pinned Baseline

Baseline inspected:
`b0f05c327012e41a34ad9b25d64b7918839461c4`.

Relevant findings:

- `postgresqleu.oauthlogin.oauthclient` dispatches OAuth providers by looking
  for hard-coded functions named `oauth_login_<provider>`. `settings.OAUTH`
  enables providers by key, and `oauthlogin/urls.py` registers matching login
  URLs, but there is no provider class registry, plugin loader, token hook, or
  post-OAuth-login signal.
- `postgresqleu.oauthlogin.views.logout` has no provider-specific logout hook.
  It delegates to Django's logout helper in the pinned baseline.
- `postgresqleu.auth` has useful signals,
  `auth_user_created_from_upstream` and `auth_user_data_received`, but those
  belong to the PostgreSQL community auth flow, not OAuth login.
- `postgresqleu.settings` supports `local_settings.py`,
  `pgeu_system_settings`, skin settings, `SKIN_APPS`, and override settings.
  That is enough to add deployment configuration and apps, but not enough to
  alter OAuth token handling or role sync without a hook in `oauthclient.py`.

Conclusion: the current role-sync behavior cannot become a clean external
plugin at this baseline without first adding an upstream OAuth extension point.
The minimal useful upstream hook would run after token fetch and userinfo
normalization, before Django login, and would receive provider name, request,
token data, normalized email/name fields, and the Django user.

## Contribution Decomposition

Recommended sequence:

1. **PR candidate: generic OIDC/Keycloak provider support.**

   Add a deployment-neutral provider path for OIDC-compatible OAuth2 providers,
   or a small Keycloak provider that follows the existing OAuth provider
   function pattern. Exclude Foss North hostnames, role names, validation users,
   local CA assumptions, and dependency pins unrelated to that provider.

2. **PR candidate: OAuth logout compatibility and provider logout hook.**

   Split Django 5 logout compatibility from OIDC end-session behavior. Upstream
   should decide whether `/accounts/logout` remains GET-compatible or templates
   move to POST logout. If OIDC logout is accepted, implement it through
   provider metadata/hooks and keep `id_token_hint` handling generic.

3. **Hook PR or plugin proposal: OAuth role-sync extension point.**

   Add a supported callback/signal for deployments to inspect token claims and
   update local Django flags/groups. The Foss North Keycloak role mapping should
   live outside generic upstream code unless upstream explicitly wants a
   configurable role-mapping feature.

4. **Local plugin after hook exists.**

   Move global and scoped Foss North mappings into a small plugin/app or
   deployment module. The plugin must preserve the exact role/path AND rule,
   prerequisite checks, provenance distinction, and safe downgrade behavior in
   the authorization runbook.

5. **Retire overlay slices only after validation.**

   Remove each patch slice only when the upstream PR or plugin replacement is
   applied at a pinned baseline and the validation gates below pass.

## Replacement Validation Gates

Any future change that replaces a patch with upstream or plugin code must pass:

- `scripts/apply-pgeu-patches.sh "${PGEU_SOURCE_DIR}"` or the replacement
  baseline/plugin apply command
- `services/pgeu/bin/preflight.sh --patched` or equivalent replacement preflight
- `scripts/smoke-integrated-stack.sh --patch-mode patched --target-ip 127.0.0.1`
- `scripts/smoke-keycloak-role-sync.sh --target-ip 127.0.0.1` for any role or
  login authorization change
- `PGEU_SCOPED_SMOKE_CONFIRM=disposable-staging
  scripts/smoke-keycloak-scoped-authorization.sh --target-ip 127.0.0.1` for any
  scoped grant, provenance, or revocation change
- `python manage.py test postgresqleu.oauthlogin.tests` for role parsing,
  prerequisites, provenance, idempotence, and revocation
- `python manage.py djangoconstraints_apply` for the overlay's declared identity
  binding and scoped-grant database constraints
- `python manage.py test postgresqleu.confwiki.tests` for the wiki edit guard
- `scripts/check-observability-baseline.sh --mode fast --target-ip 127.0.0.1`
- admin bootstrap validation for `PGEU_BOOTSTRAP_SUPERADMIN_USERS`

The replacement report must state which overlay patch was removed, which
upstream commit or plugin version replaced it, and why the behavior remains
equivalent.

## Patch Entries

Patch files live under `patches/pgeu/patches/`. Optional helper scripts may live
under `patches/pgeu/scripts/`, but every helper must be idempotent, named in the
manifest, and explain the upstream files it edits.

Use `patch-entry-template.md` for manifest entries and `PATCH_TEMPLATE.md` for
the human-readable note that explains each concrete patch.

Each future patch entry must document:

- Purpose and operator-facing rationale.
- Upstream files changed.
- Patch file path and optional helper script path.
- Apply command and validation commands.
- Whether it is `temporary-local-only`, `plugin-candidate`, or
  `pull-request-candidate`. Use `split-required` when a patch must be split
  before a plugin or upstream PR decision is valid.
- Removal criteria and upgrade notes.

## Validation

After applying the overlay, inspect:

```bash
git -C "${PGEU_SOURCE_DIR}" diff --stat
git -C "${PGEU_SOURCE_DIR}" diff --check
```

When application dependencies and settings are available in the disposable
patched checkout, also run:

```bash
python manage.py test postgresqleu.oauthlogin.tests
python manage.py test postgresqleu.confwiki.tests
python manage.py djangoconstraints_apply
```

Do not commit upstream source, runtime `.env` files, generated settings, private
keys, tokens, passwords, or generated certificate material into this repository.
