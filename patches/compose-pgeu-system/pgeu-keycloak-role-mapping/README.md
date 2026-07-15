# PGEU Keycloak role-mapping publication bundle

This directory is a secret-free, self-contained publication of the reviewed
PGEU/Keycloak authorization artifacts from `compose-pgeu-system`. It preserves
the exact patch overlay, Keycloak role and group sources, synchronization and
validation scripts, PGEU integration files, and canonical operator runbook used
for the 2026-07-15 review.

The production authority recorded by these artifacts is:

- issuer: `https://auth.foss-north.se/realms/pgeu`;
- realm and client: `pgeu`;
- client-role claim: `pgeu_roles`;
- full group-path claim: `pgeu_groups`.

The scripts and runbook deliberately reject `auth.foss-north.com` and the old
validation issuer as production substitutes.

## Production outcome — 2026-07-15

The structural rollout completed against exact issuer
`https://auth.foss-north.se/realms/pgeu`: 19 client roles, two mappers, 56
declared leaves, and 112 group-role mappings.
Final checks found zero realm group memberships, zero direct members and child
groups on every declared leaf, zero direct assignments across all twelve
scoped roles, and zero PGEU identity bindings or scoped-grant ledger rows.
Existing global direct-assignment and PGEU authorization counts were unchanged.

All nine services were healthy, integrated smoke passed, and the external auth
and site checks returned HTTP `200`. The accepted mode-restricted recovery
backup was retained, rollback was not invoked, and no production person was
assigned or granted a scoped role.

## Published contents

- `patches/pgeu/`: the complete six-patch PGEU overlay, pinned manifest,
  lifecycle notes, and patch templates.
- `scripts/apply-pgeu-patches.sh`: cumulative-prefix-aware overlay application.
- `services/pgeu/bin/preflight.sh`: patched-checkout validation.
- `services/pgeu/`: the exact container, settings renderer, entrypoint, and
  Compose fragment used by the source deployment.
- `services/keycloak/realm-pgeu.tmpl.json`: 19 client roles and the two owned
  OIDC protocol mappers.
- `services/keycloak/scoped-groups.foss-north-production.json`: 56 reviewed,
  membership-free canonical production leaf declarations.
- `scripts/sync-keycloak-role-model.sh`: idempotent role/mapper convergence.
- `scripts/sync-keycloak-scoped-groups.sh`: manifest-bounded group and leaf-role
  convergence without user-membership mutation.
- `scripts/smoke-keycloak-role-sync.sh`: credentialed global-role grant/revoke
  validation.
- `scripts/smoke-keycloak-scoped-authorization.sh`: guarded, destructive,
  disposable-staging coverage of all scoped families.
- `runbook/PGEU Authorization.md`: the exact canonical production runbook.
- `CHECKSUMS.sha256`: byte-level integrity for every exact source artifact.

The corresponding design and requirements are published at
`openspec/changes/map-pgeu-scoped-authorization/` in this repository. A concise
repository entry point is at `docs/pgeu-keycloak-role-mapping.md`.

## Authorization model

Seven global roles provide login, superadmin, and the five deployment-owned
Django manager groups. Twelve scoped roles cover series, conference,
registration, wiki, sponsor, and meeting capabilities. A scoped object grant
requires both the matching `pgeu-*` client role and its exact canonical full
group path in the same authenticated Keycloak userinfo response. Either claim
alone grants no object permission.

The production group manifest describes structure only. It contains no users,
subjects, emails, credentials, or memberships. Publishing or applying it does
not authorize assigning a person, changing `pgeu-superadmin`, or mutating an
existing user's roles.

## Reproduce the PGEU overlay

Set paths to this bundle and a disposable upstream checkout:

```bash
BUNDLE_ROOT=/path/to/fossnorth-pgeu-system/patches/compose-pgeu-system/pgeu-keycloak-role-mapping
PGEU_SOURCE_DIR=/path/to/pgeu-system

git clone https://github.com/pgeu/pgeu-system.git "$PGEU_SOURCE_DIR"
git -C "$PGEU_SOURCE_DIR" checkout b0f05c327012e41a34ad9b25d64b7918839461c4
bash "$BUNDLE_ROOT/scripts/apply-pgeu-patches.sh" "$PGEU_SOURCE_DIR"
PGEU_SOURCE_DIR="$PGEU_SOURCE_DIR" \
  bash "$BUNDLE_ROOT/services/pgeu/bin/preflight.sh" --patched
```

The apply command accepts only the pinned upstream commit and detects the exact
cumulative manifest prefix. It supports both a clean `0/6` checkout and the
previously hardened `4/6` state, and a second run must be a `6/6` no-op.

Recorded cumulative Git tree objects are:

- after patch 004: `5418477b7116ca7d4e80123820403ba7acecc343`;
- after patch 005: `0aa7d967997e3d7e02933cfa66f8ca6edb390ce5`;
- after patch 006: `e8cf2516040fc47c5701c07c8282ac2b45af1de4`.

The final focused test run against PostgreSQL 16 passed all 37 OAuth/scoped
authorization/wiki tests. The five new `util.0009` constraints were present
with their expected names. The upstream constraint-audit command also reports
unrelated historical inventory drift, documented in the runbook and not
silently represented as a globally clean audit.

## Validate Keycloak sources without mutation

These commands validate only local, secret-free inputs:

```bash
BUNDLE_ROOT=/path/to/fossnorth-pgeu-system/patches/compose-pgeu-system/pgeu-keycloak-role-mapping

bash "$BUNDLE_ROOT/scripts/sync-keycloak-role-model.sh" \
  --template "$BUNDLE_ROOT/services/keycloak/realm-pgeu.tmpl.json" \
  validate
bash "$BUNDLE_ROOT/scripts/sync-keycloak-scoped-groups.sh" \
  --manifest "$BUNDLE_ROOT/services/keycloak/scoped-groups.foss-north-production.json" \
  validate
(cd "$BUNDLE_ROOT" && sha256sum -c CHECKSUMS.sha256)
```

For live `check` or `apply`, pass absolute paths to the deployment's `.env` and
Compose file. Follow the runbook gates first; role-model convergence precedes
group convergence, and production group commands require
`--require-empty-memberships`.

```bash
bash "$BUNDLE_ROOT/scripts/sync-keycloak-role-model.sh" \
  --env-file /absolute/deployment/.env \
  --compose-file /absolute/deployment/compose.yaml \
  check
bash "$BUNDLE_ROOT/scripts/sync-keycloak-scoped-groups.sh" \
  --env-file /absolute/deployment/.env \
  --compose-file /absolute/deployment/compose.yaml \
  --manifest "$BUNDLE_ROOT/services/keycloak/scoped-groups.foss-north-production.json" \
  --require-empty-memberships \
  check
```

Do not run the scoped functional smoke against production. It hard-requires
`PGEU_SCOPED_SMOKE_CONFIRM=disposable-staging`, an explicit private target, and
refuses the production issuer.

## Integration note

The copied scripts retain their original repository-relative paths. Local
validation works directly from this bundle. Commands that contact an existing
Keycloak stack must receive the deployment's absolute env/Compose paths, or the
bundle contents must be overlaid into the same relative layout in a deployment
worktree. Secret-bearing generated realm output remains excluded from this
publication.
